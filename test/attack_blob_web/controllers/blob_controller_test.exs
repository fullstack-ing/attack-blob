defmodule AttackBlobWeb.BlobControllerTest do
  use AttackBlobWeb.ConnCase, async: false

  @test_bucket "test-bucket"

  setup do
    # Create a temporary data directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "blob_controller_test_#{:rand.uniform(1_000_000)}")
    buckets_dir = Path.join([tmp_dir, "buckets", @test_bucket])
    File.mkdir_p!(buckets_dir)

    # Configure the app to use the temp directory
    original_data_dir = Application.get_env(:attack_blob, :data_dir)
    Application.put_env(:attack_blob, :data_dir, tmp_dir)

    on_exit(fn ->
      if original_data_dir do
        Application.put_env(:attack_blob, :data_dir, original_data_dir)
      else
        Application.delete_env(:attack_blob, :data_dir)
      end

      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir, buckets_dir: buckets_dir}
  end

  describe "GET /:bucket/*key" do
    test "returns object when it exists", %{conn: conn, buckets_dir: buckets_dir} do
      # Create test file
      file_content = "Hello, World!"
      file_path = Path.join(buckets_dir, "test.txt")
      File.write!(file_path, file_content)

      conn = get(conn, "/#{@test_bucket}/test.txt")

      assert conn.status == 200
      assert conn.resp_body == file_content
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "content-length") == ["#{byte_size(file_content)}"]
      assert get_resp_header(conn, "etag") |> List.first() |> String.starts_with?("\"")
      assert get_resp_header(conn, "last-modified") != []
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "returns 404 when object does not exist", %{conn: conn} do
      conn = get(conn, "/#{@test_bucket}/nonexistent.txt")

      assert conn.status == 404
      assert json_response(conn, 404) == %{"error" => "Object not found"}
    end

    test "returns 404 when bucket does not exist", %{conn: conn} do
      conn = get(conn, "/nonexistent-bucket/test.txt")

      assert conn.status == 404
      assert json_response(conn, 404) == %{"error" => "Object not found"}
    end

    test "handles nested object paths", %{conn: conn, buckets_dir: buckets_dir} do
      # Create nested file
      nested_path = Path.join([buckets_dir, "path", "to"])
      File.mkdir_p!(nested_path)
      file_path = Path.join(nested_path, "file.txt")
      File.write!(file_path, "nested content")

      conn = get(conn, "/#{@test_bucket}/path/to/file.txt")

      assert conn.status == 200
      assert conn.resp_body == "nested content"
    end

    test "sets correct content-type for different file types", %{
      conn: conn,
      buckets_dir: buckets_dir
    } do
      # Test various file types
      test_files = [
        {"image.jpg", "fake jpeg data", "image/jpeg"},
        {"document.pdf", "fake pdf data", "application/pdf"},
        {"data.json", ~s({"key": "value"}), "application/json"},
        {"page.html", "<html></html>", "text/html"}
      ]

      for {filename, content, expected_type} <- test_files do
        File.write!(Path.join(buckets_dir, filename), content)
        conn = get(conn, "/#{@test_bucket}/#{filename}")

        assert conn.status == 200

        assert get_resp_header(conn, "content-type") == [expected_type],
               "Expected #{expected_type} for #{filename}"
      end
    end

    test "calculates correct ETag", %{conn: conn, buckets_dir: buckets_dir} do
      content = "test content for etag"
      file_path = Path.join(buckets_dir, "etag-test.txt")
      File.write!(file_path, content)

      conn1 = get(conn, "/#{@test_bucket}/etag-test.txt")
      etag1 = get_resp_header(conn1, "etag") |> List.first()

      # Same file should produce same ETag
      conn2 = get(conn, "/#{@test_bucket}/etag-test.txt")
      etag2 = get_resp_header(conn2, "etag") |> List.first()

      assert etag1 == etag2
      assert String.starts_with?(etag1, "\"")
      assert String.ends_with?(etag1, "\"")
    end

    test "rejects path traversal attempts", %{conn: conn} do
      # Various path traversal attempts
      traversal_attempts = [
        "../etc/passwd",
        "../../secret.txt",
        "path/../../../etc/passwd",
        "./../file.txt"
      ]

      for attempt <- traversal_attempts do
        conn = get(conn, "/#{@test_bucket}/#{attempt}")
        assert conn.status == 400
        assert json_response(conn, 400) == %{"error" => "Invalid object key"}
      end
    end

    test "rejects invalid object keys", %{conn: conn} do
      invalid_keys = [
        "/absolute/path.txt",
        # Absolute path
        "file\x00name.txt"
        # Null byte
      ]

      for key <- invalid_keys do
        conn = get(conn, "/#{@test_bucket}/#{key}")
        assert conn.status in [400, 404]
      end
    end

    test "rejects invalid bucket names", %{conn: conn} do
      invalid_buckets = [
        "AB",
        # Too short
        "Invalid_Bucket",
        # Uppercase and underscore
        "bucket-",
        # Ends with hyphen
        "-bucket"
        # Starts with hyphen
      ]

      for bucket <- invalid_buckets do
        conn = get(conn, "/#{bucket}/test.txt")
        assert conn.status == 400
        assert json_response(conn, 400) == %{"error" => "Invalid bucket name"}
      end
    end

    test "returns 404 when path is a directory", %{conn: conn, buckets_dir: buckets_dir} do
      # Create a directory
      dir_path = Path.join(buckets_dir, "directory")
      File.mkdir_p!(dir_path)

      conn = get(conn, "/#{@test_bucket}/directory")

      assert conn.status == 404
      assert json_response(conn, 404) == %{"error" => "Object not found"}
    end
  end

  describe "HEAD /:bucket/*key" do
    test "returns headers without body when object exists", %{
      conn: conn,
      buckets_dir: buckets_dir
    } do
      # Create test file
      file_content = "Hello, World!"
      file_path = Path.join(buckets_dir, "test.txt")
      File.write!(file_path, file_content)

      conn = head(conn, "/#{@test_bucket}/test.txt")

      assert conn.status == 200
      assert conn.resp_body == ""
      assert get_resp_header(conn, "content-type") == ["text/plain"]
      assert get_resp_header(conn, "content-length") == ["#{byte_size(file_content)}"]
      assert get_resp_header(conn, "etag") |> List.first() |> String.starts_with?("\"")
      assert get_resp_header(conn, "last-modified") != []
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    end

    test "returns 404 when object does not exist", %{conn: conn} do
      conn = head(conn, "/#{@test_bucket}/nonexistent.txt")

      assert conn.status == 404
      # HEAD responses have empty body
      assert conn.resp_body == ""
    end

    test "returns same headers as GET request", %{conn: conn, buckets_dir: buckets_dir} do
      file_content = "test content"
      file_path = Path.join(buckets_dir, "same-headers.txt")
      File.write!(file_path, file_content)

      get_conn = get(conn, "/#{@test_bucket}/same-headers.txt")
      head_conn = head(conn, "/#{@test_bucket}/same-headers.txt")

      assert get_resp_header(get_conn, "content-type") ==
               get_resp_header(head_conn, "content-type")

      assert get_resp_header(get_conn, "content-length") ==
               get_resp_header(head_conn, "content-length")

      assert get_resp_header(get_conn, "etag") == get_resp_header(head_conn, "etag")

      assert get_resp_header(get_conn, "cache-control") ==
               get_resp_header(head_conn, "cache-control")
    end

    test "rejects path traversal attempts", %{conn: conn} do
      conn = head(conn, "/#{@test_bucket}/../etc/passwd")

      assert conn.status == 400
      # HEAD responses have empty body
      assert conn.resp_body == ""
    end

    test "rejects invalid bucket names", %{conn: conn} do
      conn = head(conn, "/INVALID/test.txt")

      assert conn.status == 400
      # HEAD responses have empty body
      assert conn.resp_body == ""
    end
  end

  describe "DELETE /:bucket/*key" do
    test "returns 401 when authorization header is missing", %{conn: conn} do
      conn = delete(conn, "/#{@test_bucket}/test.txt")

      assert conn.status == 401
      assert json_response(conn, 401) == %{"error" => "Missing authorization header"}
    end

    test "returns 400 for invalid bucket name", %{conn: conn} do
      conn = delete(conn, "/INVALID/test.txt")

      assert conn.status == 400
      assert json_response(conn, 400) == %{"error" => "Invalid bucket name"}
    end

    test "returns 400 for invalid object key", %{conn: conn} do
      conn = delete(conn, "/#{@test_bucket}/../etc/passwd")

      assert conn.status == 400
      assert json_response(conn, 400) == %{"error" => "Invalid object key"}
    end

    test "returns 401 for invalid authorization format", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> delete("/#{@test_bucket}/test.txt")

      assert conn.status == 401
      assert json_response(conn, 401) == %{"error" => "Missing authorization header"}
    end
  end

  describe "GET /:bucket" do
    test "returns empty list for empty bucket", %{conn: conn} do
      conn = get(conn, "/#{@test_bucket}")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["bucket"] == @test_bucket
      assert response["objects"] == []
      assert response["key_count"] == 0
      assert response["is_truncated"] == false
    end

    test "lists all objects in bucket", %{conn: conn, buckets_dir: buckets_dir} do
      # Create test files
      File.write!(Path.join(buckets_dir, "file1.txt"), "content1")
      File.write!(Path.join(buckets_dir, "file2.txt"), "content2")
      File.write!(Path.join(buckets_dir, "file3.txt"), "content3")

      conn = get(conn, "/#{@test_bucket}")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["bucket"] == @test_bucket
      assert response["key_count"] == 3
      assert length(response["objects"]) == 3

      keys = Enum.map(response["objects"], & &1["key"]) |> Enum.sort()
      assert keys == ["file1.txt", "file2.txt", "file3.txt"]
    end

    test "returns object metadata", %{conn: conn, buckets_dir: buckets_dir} do
      content = "test content"
      File.write!(Path.join(buckets_dir, "test.txt"), content)

      conn = get(conn, "/#{@test_bucket}")

      assert conn.status == 200
      response = json_response(conn, 200)

      [object] = response["objects"]
      assert object["key"] == "test.txt"
      assert object["size"] == byte_size(content)
      assert object["last_modified"]
      assert object["etag"]
    end

    test "lists nested objects", %{conn: conn, buckets_dir: buckets_dir} do
      # Create nested structure
      nested_dir = Path.join([buckets_dir, "folder", "subfolder"])
      File.mkdir_p!(nested_dir)

      File.write!(Path.join(buckets_dir, "root.txt"), "root")
      File.write!(Path.join([buckets_dir, "folder", "level1.txt"]), "level1")
      File.write!(Path.join(nested_dir, "deep.txt"), "deep")

      conn = get(conn, "/#{@test_bucket}")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["key_count"] == 3

      keys = Enum.map(response["objects"], & &1["key"]) |> Enum.sort()
      assert keys == ["folder/level1.txt", "folder/subfolder/deep.txt", "root.txt"]
    end

    test "filters objects by prefix", %{conn: conn, buckets_dir: buckets_dir} do
      File.mkdir_p!(Path.join(buckets_dir, "docs"))
      File.mkdir_p!(Path.join(buckets_dir, "images"))
      File.write!(Path.join(buckets_dir, "docs/readme.md"), "readme")
      File.write!(Path.join(buckets_dir, "docs/guide.md"), "guide")
      File.write!(Path.join(buckets_dir, "images/photo.jpg"), "photo")

      conn = get(conn, "/#{@test_bucket}?prefix=docs/")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["prefix"] == "docs/"
      assert response["key_count"] == 2

      keys = Enum.map(response["objects"], & &1["key"]) |> Enum.sort()
      assert keys == ["docs/guide.md", "docs/readme.md"]
    end

    test "groups objects by delimiter", %{conn: conn, buckets_dir: buckets_dir} do
      # Create folder structure
      File.mkdir_p!(Path.join(buckets_dir, "docs"))
      File.mkdir_p!(Path.join(buckets_dir, "images"))
      File.write!(Path.join(buckets_dir, "root.txt"), "root")
      File.write!(Path.join(buckets_dir, "docs/file1.txt"), "file1")
      File.write!(Path.join(buckets_dir, "docs/file2.txt"), "file2")
      File.write!(Path.join(buckets_dir, "images/photo.jpg"), "photo")

      conn = get(conn, "/#{@test_bucket}?delimiter=/")

      assert conn.status == 200
      response = json_response(conn, 200)

      # Should have root.txt as object
      object_keys = Enum.map(response["objects"], & &1["key"])
      assert "root.txt" in object_keys

      # Should have docs/ and images/ as common prefixes
      common_prefixes = response["common_prefixes"] |> Enum.sort()
      assert common_prefixes == ["docs/", "images/"]
    end

    test "combines prefix and delimiter", %{conn: conn, buckets_dir: buckets_dir} do
      File.mkdir_p!(Path.join(buckets_dir, "docs/api"))
      File.mkdir_p!(Path.join(buckets_dir, "docs/guide"))
      File.write!(Path.join(buckets_dir, "docs/readme.md"), "readme")
      File.write!(Path.join(buckets_dir, "docs/api/endpoint1.md"), "endpoint1")
      File.write!(Path.join(buckets_dir, "docs/api/endpoint2.md"), "endpoint2")
      File.write!(Path.join(buckets_dir, "docs/guide/intro.md"), "intro")

      conn = get(conn, "/#{@test_bucket}?prefix=docs/&delimiter=/")

      assert conn.status == 200
      response = json_response(conn, 200)

      # Should list readme.md directly under docs/
      object_keys = Enum.map(response["objects"], & &1["key"])
      assert "docs/readme.md" in object_keys

      # Should have docs/api/ and docs/guide/ as common prefixes
      common_prefixes = response["common_prefixes"] |> Enum.sort()
      assert common_prefixes == ["docs/api/", "docs/guide/"]
    end

    test "respects max_keys parameter", %{conn: conn, buckets_dir: buckets_dir} do
      # Create 5 files
      for i <- 1..5 do
        File.write!(Path.join(buckets_dir, "file#{i}.txt"), "content#{i}")
      end

      conn = get(conn, "/#{@test_bucket}?max_keys=3")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["key_count"] == 3
      assert response["is_truncated"] == true
    end

    test "max_keys defaults to 1000", %{conn: conn, buckets_dir: buckets_dir} do
      File.write!(Path.join(buckets_dir, "file.txt"), "content")

      conn = get(conn, "/#{@test_bucket}")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["is_truncated"] == false
    end

    test "max_keys caps at 1000", %{conn: conn, buckets_dir: buckets_dir} do
      File.write!(Path.join(buckets_dir, "file.txt"), "content")

      conn = get(conn, "/#{@test_bucket}?max_keys=5000")

      assert conn.status == 200
      response = json_response(conn, 200)

      # Should be capped at 1000
      assert response["is_truncated"] == false
    end

    test "returns 404 for non-existent bucket", %{conn: conn} do
      conn = get(conn, "/nonexistent-bucket")

      assert conn.status == 404
      assert json_response(conn, 404) == %{"error" => "Bucket not found"}
    end

    test "returns 400 for invalid bucket name", %{conn: conn} do
      conn = get(conn, "/INVALID")

      assert conn.status == 400
      assert json_response(conn, 400) == %{"error" => "Invalid bucket name"}
    end

    test "handles empty prefix parameter", %{conn: conn, buckets_dir: buckets_dir} do
      File.write!(Path.join(buckets_dir, "file.txt"), "content")

      conn = get(conn, "/#{@test_bucket}?prefix=")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["prefix"] == ""
      assert response["key_count"] == 1
    end
  end
end
