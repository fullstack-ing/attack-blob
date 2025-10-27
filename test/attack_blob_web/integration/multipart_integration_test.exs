defmodule AttackBlobWeb.Integration.MultipartIntegrationTest do
  use ExUnit.Case, async: false

  alias AttackBlob.KeyManager
  alias AttackBlob.Test.Presigner

  @test_bucket "multipart-test-bucket"
  @endpoint "http://localhost:4002"

  setup_all do
    # Use the actual data directory that KeyManager is already watching
    actual_data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    actual_keys_dir = Path.join(actual_data_dir, "keys")
    actual_buckets_dir = Path.join([actual_data_dir, "buckets", @test_bucket])
    actual_multipart_dir = Path.join(actual_data_dir, "multipart")

    File.mkdir_p!(actual_keys_dir)
    File.mkdir_p!(actual_buckets_dir)
    File.mkdir_p!(actual_multipart_dir)

    # Generate unique access key for this test run
    access_key_id = "AKIATEST#{:rand.uniform(1_000_000)}"
    secret_key = "test-secret-key-#{:rand.uniform(1_000_000)}"

    key_data = %{
      access_key_id: access_key_id,
      secret_key: secret_key,
      bucket: @test_bucket,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      permissions: ["put", "delete"]
    }

    key_file = Path.join(actual_keys_dir, "#{access_key_id}.json")
    File.write!(key_file, Jason.encode!(key_data, pretty: true))
    File.chmod!(key_file, 0o600)

    # Reload KeyManager to pick up new key
    :ok = KeyManager.reload()

    # Give KeyManager time to reload
    Process.sleep(50)

    # Verify key was loaded
    case KeyManager.lookup(access_key_id) do
      {:ok, _key} ->
        :ok

      :error ->
        raise "Test setup failed: KeyManager did not load test key #{access_key_id}"
    end

    on_exit(fn ->
      # Clean up test key and bucket
      File.rm(key_file)
      File.rm_rf!(actual_buckets_dir)
      File.rm_rf!(actual_multipart_dir)
      :ok = KeyManager.reload()
    end)

    config = %{
      endpoint: @endpoint,
      access_key_id: access_key_id,
      secret_access_key: secret_key,
      region: "us-east-1"
    }

    %{
      config: config,
      bucket_path: actual_buckets_dir,
      multipart_dir: actual_multipart_dir
    }
  end

  describe "Multipart upload workflow" do
    test "complete multipart upload workflow - initiate, upload parts, complete", %{config: config} do
      key = "large-file-#{:rand.uniform(100_000)}.txt"

      # Part 1: Initiate multipart upload
      initiate_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :post,
          query_params: %{"uploads" => ""}
        )

      {:ok, initiate_response} = Req.post(initiate_url, body: "")

      assert initiate_response.status == 200
      assert initiate_response.body =~ "<InitiateMultipartUploadResult"
      assert initiate_response.body =~ "<UploadId>"

      # Extract upload ID from XML response
      upload_id = extract_upload_id(initiate_response.body)
      assert is_binary(upload_id)

      # Part 2: Upload parts
      part1_data = "This is part 1 content. " |> String.duplicate(100)
      part2_data = "This is part 2 content. " |> String.duplicate(100)

      # Upload part 1
      part1_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :put,
          query_params: %{"partNumber" => "1", "uploadId" => upload_id}
        )

      {:ok, part1_response} = Req.put(part1_url, body: part1_data)

      assert part1_response.status == 200
      part1_etag = get_etag_header(part1_response)
      assert part1_etag != nil

      # Upload part 2
      part2_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :put,
          query_params: %{"partNumber" => "2", "uploadId" => upload_id}
        )

      {:ok, part2_response} = Req.put(part2_url, body: part2_data, receive_timeout: 30_000)

      assert part2_response.status == 200
      part2_etag = get_etag_header(part2_response)
      assert part2_etag != nil

      # Part 3: Complete multipart upload
      complete_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :post,
          query_params: %{"uploadId" => upload_id}
        )

      # CompleteMultipartUpload requires an XML body with part list
      complete_body = """
      <CompleteMultipartUpload>
        <Part>
          <PartNumber>1</PartNumber>
          <ETag>#{part1_etag}</ETag>
        </Part>
        <Part>
          <PartNumber>2</PartNumber>
          <ETag>#{part2_etag}</ETag>
        </Part>
      </CompleteMultipartUpload>
      """

      {:ok, complete_response} = Req.post(complete_url, body: complete_body)

      assert complete_response.status == 200
      assert complete_response.body =~ "<CompleteMultipartUploadResult"
      assert complete_response.body =~ "<ETag>"

      # Verify the assembled file exists and contains both parts
      data_dir = Application.get_env(:attack_blob, :data_dir)
      final_path = Path.join([data_dir, "buckets", @test_bucket, key])
      assert File.exists?(final_path)

      final_content = File.read!(final_path)
      assert final_content == part1_data <> part2_data
    end

    test "abort multipart upload cleans up parts", %{config: config} do
      key = "aborted-file-#{:rand.uniform(100_000)}.txt"

      # Initiate multipart upload
      initiate_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :post, query_params: %{"uploads" => ""})
      

      {:ok, initiate_response} = Req.post(initiate_url, body: "")

      assert initiate_response.status == 200
      upload_id = extract_upload_id(initiate_response.body)

      # Upload a part
      part1_data = "Test part data"

      part1_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :put, query_params: %{"partNumber" => "1", "uploadId" => upload_id})
      

      {:ok, part1_response} = Req.put(part1_url, body: part1_data)

      assert part1_response.status == 200

      # Verify part file exists
      data_dir = Application.get_env(:attack_blob, :data_dir)
      parts_dir = Path.join([data_dir, "multipart", upload_id])
      part_file = Path.join(parts_dir, "part-1")
      assert File.exists?(part_file)

      # Abort the upload
      abort_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :delete, query_params: %{"uploadId" => upload_id})
      

      {:ok, abort_response} = Req.delete(abort_url)

      assert abort_response.status == 204

      # Verify parts directory is cleaned up
      refute File.exists?(parts_dir)
    end

    test "rejects upload with invalid upload ID", %{config: config} do
      key = "invalid-upload-#{:rand.uniform(100_000)}.txt"

      fake_upload_id = "invalid-upload-id"
      part_data = "Test data"

      part_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :put, query_params: %{"partNumber" => "1", "uploadId" => fake_upload_id})
      

      {:ok, response} = Req.put(part_url, body: part_data)

      assert response.status == 404
    end

    test "rejects complete with non-existent upload ID", %{config: config} do
      key = "nonexistent-upload-#{:rand.uniform(100_000)}.txt"

      fake_upload_id = "nonexistent-upload-id"

      complete_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :post, query_params: %{"uploadId" => fake_upload_id})
      

      complete_body = """
      <CompleteMultipartUpload>
        <Part>
          <PartNumber>1</PartNumber>
          <ETag>"abc123"</ETag>
        </Part>
      </CompleteMultipartUpload>
      """

      {:ok, response} = Req.post(complete_url, body: complete_body)

      assert response.status == 404
    end

    test "rejects part upload with invalid signature", %{config: config} do
      key = "invalid-sig-#{:rand.uniform(100_000)}.txt"

      # Initiate multipart upload
      initiate_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :post, query_params: %{"uploads" => ""})
      

      {:ok, initiate_response} = Req.post(initiate_url, body: "")

      upload_id = extract_upload_id(initiate_response.body)

      # Try to upload part with wrong signature (use wrong access key)
      wrong_config = %{config | secret_access_key: "wrong-secret-key"}

      part_data = "Test data"

      part_url =
        Presigner.presign_url(wrong_config,
          bucket: @test_bucket,
          key: key,
          method: :put,
          query_params: %{"partNumber" => "1", "uploadId" => upload_id}
        )

      {:ok, response} = Req.put(part_url, body: part_data)

      assert response.status == 403
    end

    test "upload multiple small parts and verify assembly order", %{config: config} do
      key = "multi-part-#{:rand.uniform(100_000)}.txt"

      # Initiate
      initiate_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :post, query_params: %{"uploads" => ""})
      

      {:ok, initiate_response} = Req.post(initiate_url, body: "")

      upload_id = extract_upload_id(initiate_response.body)

      # Upload 5 parts with distinct content
      parts =
        for part_num <- 1..5 do
          part_data = "Part #{part_num} data\n"

          part_url =
            Presigner.presign_url(config,
              bucket: @test_bucket,
              key: key,
              method: :put,
              query_params: %{"partNumber" => "#{part_num}", "uploadId" => upload_id}
            )

          {:ok, response} = Req.put(part_url, body: part_data)

          assert response.status == 200
          etag = get_etag_header(response)
          {part_num, etag}
        end

      # Complete with all parts
      complete_body =
        "<CompleteMultipartUpload>\n" <>
          Enum.map_join(parts, "\n", fn {num, etag} ->
            "  <Part><PartNumber>#{num}</PartNumber><ETag>#{etag}</ETag></Part>"
          end) <>
          "\n</CompleteMultipartUpload>"

      complete_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :post,
          query_params: %{"uploadId" => upload_id}
        )

      {:ok, complete_response} = Req.post(complete_url, body: complete_body)

      assert complete_response.status == 200

      # Verify assembled file has parts in correct order
      data_dir = Application.get_env(:attack_blob, :data_dir)
      final_path = Path.join([data_dir, "buckets", @test_bucket, key])
      final_content = File.read!(final_path)

      expected =
        Enum.map_join(1..5, "", fn num ->
          "Part #{num} data\n"
        end)

      assert final_content == expected
    end
  end

  ## Helper Functions

  defp extract_upload_id(xml_body) when is_binary(xml_body) do
    # Simple regex to extract upload ID from XML
    case Regex.run(~r/<UploadId>([^<]+)<\/UploadId>/, xml_body) do
      [_, upload_id] -> upload_id
      _ -> nil
    end
  end

  defp extract_upload_id(_), do: nil

  defp get_etag_header(response) do
    case Enum.find(response.headers, fn {k, _v} -> String.downcase(k) == "etag" end) do
      {_, etag} -> etag
      _ -> nil
    end
  end
end
