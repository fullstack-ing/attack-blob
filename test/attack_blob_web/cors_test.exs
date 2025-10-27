defmodule AttackBlobWeb.CorsTest do
  use AttackBlobWeb.ConnCase, async: true

  describe "CORS headers" do
    test "includes CORS headers on GET requests", %{conn: conn} do
      # Create a test bucket and file
      bucket = "cors-test-bucket"
      key = "test-file.txt"
      content = "CORS test content"

      data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
      bucket_path = Path.join([data_dir, "buckets", bucket])
      File.mkdir_p!(bucket_path)
      file_path = Path.join(bucket_path, key)
      File.write!(file_path, content)

      # Make request with Origin header
      conn =
        conn
        |> put_req_header("origin", "https://example.com")
        |> get("/#{bucket}/#{key}")

      # Should include CORS headers
      assert get_resp_header(conn, "access-control-allow-origin") != []

      # Cleanup
      File.rm_rf!(bucket_path)
    end

    test "handles preflight OPTIONS requests", %{conn: conn} do
      bucket = "cors-preflight-bucket"
      key = "test.txt"

      # Make preflight request
      conn =
        conn
        |> put_req_header("origin", "https://example.com")
        |> put_req_header("access-control-request-method", "PUT")
        |> put_req_header("access-control-request-headers", "content-type")
        |> options("/#{bucket}/#{key}")

      # Should return 200 with CORS headers
      assert conn.status == 200
      assert get_resp_header(conn, "access-control-allow-origin") != []
      assert get_resp_header(conn, "access-control-allow-methods") != []
    end

    test "includes CORS headers on list bucket requests", %{conn: conn} do
      bucket = "cors-list-bucket"

      data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
      bucket_path = Path.join([data_dir, "buckets", bucket])
      File.mkdir_p!(bucket_path)

      conn =
        conn
        |> put_req_header("origin", "https://example.com")
        |> get("/#{bucket}")

      assert get_resp_header(conn, "access-control-allow-origin") != []

      # Cleanup
      File.rm_rf!(bucket_path)
    end
  end
end
