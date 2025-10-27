defmodule AttackBlobWeb.MultipartUploadTest do
  use ExUnit.Case, async: false

  alias AttackBlob.MultipartUpload

  describe "MultipartUpload GenServer" do
    test "initiate creates a new upload" do
      {:ok, upload_id} = MultipartUpload.initiate("test-bucket", "test-key.txt")

      assert is_binary(upload_id)
      assert {:ok, info} = MultipartUpload.get_upload(upload_id)
      assert info.bucket == "test-bucket"
      assert info.key == "test-key.txt"
      assert info.parts == %{}

      # Cleanup
      MultipartUpload.abort(upload_id)
    end

    test "add_part records a part" do
      {:ok, upload_id} = MultipartUpload.initiate("bucket", "key.txt")

      :ok = MultipartUpload.add_part(upload_id, 1, "etag123", 1024)

      {:ok, upload_info} = MultipartUpload.get_upload(upload_id)
      assert Map.has_key?(upload_info.parts, 1)
      assert upload_info.parts[1].etag == "etag123"
      assert upload_info.parts[1].size == 1024

      # Cleanup
      MultipartUpload.abort(upload_id)
    end

    test "add_part returns error for non-existent upload" do
      result = MultipartUpload.add_part("nonexistent", 1, "etag", 100)
      assert result == {:error, :upload_not_found}
    end

    test "list_parts returns sorted parts" do
      {:ok, upload_id} = MultipartUpload.initiate("bucket", "key.txt")

      MultipartUpload.add_part(upload_id, 3, "etag3", 300)
      MultipartUpload.add_part(upload_id, 1, "etag1", 100)
      MultipartUpload.add_part(upload_id, 2, "etag2", 200)

      {:ok, parts} = MultipartUpload.list_parts(upload_id)

      assert length(parts) == 3
      assert Enum.at(parts, 0).part_number == 1
      assert Enum.at(parts, 1).part_number == 2
      assert Enum.at(parts, 2).part_number == 3

      # Cleanup
      MultipartUpload.abort(upload_id)
    end

    test "complete removes upload from tracking" do
      {:ok, upload_id} = MultipartUpload.initiate("bucket", "key.txt")
      MultipartUpload.add_part(upload_id, 1, "etag1", 100)

      {:ok, info} = MultipartUpload.complete(upload_id)

      assert info.bucket == "bucket"
      assert info.key == "key.txt"
      assert map_size(info.parts) == 1

      # Should be gone now
      assert {:error, :not_found} = MultipartUpload.get_upload(upload_id)
    end

    test "abort removes upload from tracking" do
      {:ok, upload_id} = MultipartUpload.initiate("bucket", "key.txt")

      :ok = MultipartUpload.abort(upload_id)

      assert {:error, :not_found} = MultipartUpload.get_upload(upload_id)
    end

    test "list_uploads returns uploads for a bucket" do
      {:ok, upload_id1} = MultipartUpload.initiate("bucket1", "key1.txt")
      {:ok, upload_id2} = MultipartUpload.initiate("bucket1", "key2.txt")
      {:ok, upload_id3} = MultipartUpload.initiate("bucket2", "key3.txt")

      uploads = MultipartUpload.list_uploads("bucket1")

      assert length(uploads) == 2
      assert Enum.any?(uploads, &(&1.upload_id == upload_id1))
      assert Enum.any?(uploads, &(&1.upload_id == upload_id2))
      refute Enum.any?(uploads, &(&1.upload_id == upload_id3))

      # Cleanup
      MultipartUpload.abort(upload_id1)
      MultipartUpload.abort(upload_id2)
      MultipartUpload.abort(upload_id3)
    end
  end

  describe "Part file operations" do
    test "writes and assembles parts correctly" do
      data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
      bucket = "test-multipart-bucket"
      key = "assembled-file.txt"

      # Create test bucket
      bucket_path = Path.join([data_dir, "buckets", bucket])
      File.mkdir_p!(bucket_path)

      {:ok, upload_id} = MultipartUpload.initiate(bucket, key)

      # Write parts directly to simulate upload
      parts_dir = Path.join([data_dir, "multipart", upload_id])
      File.mkdir_p!(parts_dir)

      File.write!(Path.join(parts_dir, "part-1"), "Part 1 ")
      File.write!(Path.join(parts_dir, "part-2"), "Part 2 ")
      File.write!(Path.join(parts_dir, "part-3"), "Part 3")

      # Record parts in MultipartUpload
      MultipartUpload.add_part(upload_id, 1, "etag1", 7)
      MultipartUpload.add_part(upload_id, 2, "etag2", 7)
      MultipartUpload.add_part(upload_id, 3, "etag3", 6)

      # Complete the upload (this will trigger assembly)
      {:ok, upload_info} = MultipartUpload.complete(upload_id)

      # Manually assemble parts (simulating what the controller does)
      final_path = Path.join(bucket_path, key)

      case File.open(final_path, [:write, :binary]) do
        {:ok, file} ->
          for {part_num, _} <- Enum.sort(upload_info.parts) do
            part_file = Path.join(parts_dir, "part-#{part_num}")
            {:ok, data} = File.read(part_file)
            IO.binwrite(file, data)
          end

          File.close(file)
      end

      # Verify assembled file
      assert File.exists?(final_path)
      content = File.read!(final_path)
      assert content == "Part 1 Part 2 Part 3"

      # Cleanup
      File.rm_rf!(parts_dir)
      File.rm_rf!(bucket_path)
    end
  end
end
