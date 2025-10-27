defmodule AttackBlobWeb.Integration.PresignedUrlTest do
  use ExUnit.Case, async: false

  alias AttackBlob.Test.Presigner

  @test_bucket "presigned-test-bucket"
  @endpoint "http://localhost:4002"

  setup_all do
    # Get the actual data directory that KeyManager is using
    actual_data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    actual_keys_dir = Path.join(actual_data_dir, "keys")
    actual_buckets_dir = Path.join([actual_data_dir, "buckets", @test_bucket])

    File.mkdir_p!(actual_keys_dir)
    File.mkdir_p!(actual_buckets_dir)

    # Generate test access key
    access_key_id = "AKIATEST#{:rand.uniform(1_000_000)}"
    secret_key = generate_secret_key()

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
    :ok = AttackBlob.KeyManager.reload()

    # Give KeyManager time to reload
    Process.sleep(50)

    # Verify key was loaded
    case AttackBlob.KeyManager.lookup(access_key_id) do
      {:ok, _key} -> :ok
      :error -> raise "Test setup failed: KeyManager did not load test key #{access_key_id}"
    end

    on_exit(fn ->
      # Clean up test key and bucket
      File.rm(key_file)
      File.rm_rf!(actual_buckets_dir)
      :ok = AttackBlob.KeyManager.reload()
    end)

    config = %{
      endpoint: @endpoint,
      access_key_id: access_key_id,
      secret_access_key: secret_key,
      region: "us-east-1"
    }

    %{config: config, buckets_dir: actual_buckets_dir}
  end

  describe "PUT with presigned URL" do
    test "successfully uploads a file", %{config: config} do
      key = "test-file-#{:rand.uniform(1_000_000)}.txt"
      content = "Hello, presigned world!"

      # Generate presigned URL
      signed_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :put)

      # Make PUT request
      response = Req.put!(signed_url, body: content)

      assert response.status == 200
      assert response.headers["etag"]
    end

    test "uploads binary data", %{config: config} do
      key = "binary-#{:rand.uniform(1_000_000)}.bin"
      content = :crypto.strong_rand_bytes(1024)

      signed_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :put)

      response = Req.put!(signed_url, body: content)

      assert response.status == 200
    end

    test "uploads with additional headers", %{config: config} do
      key = "with-headers-#{:rand.uniform(1_000_000)}.txt"
      content = "Test content"

      signed_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :put,
          headers: %{"Cache-Control" => "max-age=31536000"}
        )

      response =
        Req.put!(signed_url,
          body: content,
          headers: [{"cache-control", "max-age=31536000"}]
        )

      assert response.status == 200
    end

    test "rejects request with wrong signature", %{config: config} do
      key = "wrong-sig-#{:rand.uniform(1_000_000)}.txt"
      content = "This should fail"

      # Generate presigned URL with correct signature
      signed_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :put)

      # Tamper with the signature
      tampered_url =
        String.replace(signed_url, ~r/X-Amz-Signature=[^&]+/, "X-Amz-Signature=badsig")

      response = Req.put(tampered_url, body: content)

      assert {:ok, %{status: 403}} = response
    end

    test "rejects expired presigned URL", %{config: config} do
      key = "expired-#{:rand.uniform(1_000_000)}.txt"
      content = "Expired request"

      # Create a presigned URL with a datetime 2 hours in the past and 1 second expiry
      past_datetime = DateTime.utc_now() |> DateTime.add(-7200, :second)

      signed_url =
        Presigner.presign_url(config,
          bucket: @test_bucket,
          key: key,
          method: :put,
          request_datetime: past_datetime,
          link_expiry: 1
        )

      response = Req.put(signed_url, body: content)

      # Should fail (either 403 or signature mismatch due to time)
      assert {:ok, %{status: status}} = response
      assert status in [403, 400]
    end
  end

  describe "DELETE with presigned URL" do
    test "successfully deletes a file", %{config: config, buckets_dir: buckets_dir} do
      key = "to-delete-#{:rand.uniform(1_000_000)}.txt"
      content = "Delete me"

      # First upload the file
      file_path = Path.join(buckets_dir, key)
      File.write!(file_path, content)

      # Generate presigned DELETE URL
      signed_url =
        Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :delete)

      # Make DELETE request
      response = Req.delete!(signed_url)

      assert response.status == 204
      refute File.exists?(file_path)
    end

    test "returns 404 when deleting non-existent file", %{config: config} do
      key = "non-existent-#{:rand.uniform(1_000_000)}.txt"

      signed_url =
        Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :delete)

      response = Req.delete(signed_url)

      assert {:ok, %{status: 404}} = response
    end

    test "rejects DELETE with wrong signature", %{config: config, buckets_dir: buckets_dir} do
      key = "delete-wrong-sig-#{:rand.uniform(1_000_000)}.txt"

      # Create the file
      file_path = Path.join(buckets_dir, key)
      File.write!(file_path, "Should not be deleted")

      # Generate presigned URL
      signed_url =
        Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :delete)

      # Tamper with signature
      tampered_url =
        String.replace(signed_url, ~r/X-Amz-Signature=[^&]+/, "X-Amz-Signature=badsig")

      response = Req.delete(tampered_url)

      assert {:ok, %{status: 403}} = response
      # File should still exist
      assert File.exists?(file_path)
    end
  end

  describe "PUT and GET workflow" do
    test "upload file then retrieve it", %{config: config} do
      key = "upload-then-get-#{:rand.uniform(1_000_000)}.txt"
      content = "Upload and retrieve test"

      # Upload with presigned URL
      signed_put_url = Presigner.presign_url(config, bucket: @test_bucket, key: key, method: :put)
      put_response = Req.put!(signed_put_url, body: content)
      assert put_response.status == 200
      etag = put_response.headers["etag"] |> List.first()

      # Retrieve with regular GET (no auth required)
      get_url = "#{@endpoint}/#{@test_bucket}/#{key}"
      get_response = Req.get!(get_url)

      assert get_response.status == 200
      assert get_response.body == content
      assert get_response.headers["etag"] |> List.first() == etag
    end
  end

  describe "presigned URL with different buckets" do
    test "rejects upload to wrong bucket", %{config: config} do
      key = "wrong-bucket-#{:rand.uniform(1_000_000)}.txt"

      # Try to upload to a different bucket
      wrong_bucket_config = %{config | access_key_id: config.access_key_id}

      signed_url =
        Presigner.presign_url(wrong_bucket_config,
          bucket: "different-bucket",
          key: key,
          method: :put
        )

      response = Req.put(signed_url, body: "Should fail")

      # Should fail with 403 (bucket access denied)
      assert {:ok, %{status: 403}} = response
    end
  end

  ## Helper Functions

  defp generate_secret_key do
    :crypto.strong_rand_bytes(30)
    |> Base.encode64()
    |> binary_part(0, 40)
  end
end
