defmodule AttackBlobWeb.CorsTest do
  use AttackBlobWeb.ConnCase, async: false

  setup do
    # Create a temporary data directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "cors_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

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

    %{tmp_dir: tmp_dir}
  end

  describe "CORS headers" do
    test "includes CORS headers on GET requests", %{conn: conn, tmp_dir: tmp_dir} do
      # Create a test bucket and file
      bucket = "cors-test-bucket"
      key = "test-file.txt"
      content = "CORS test content"

      bucket_path = Path.join([tmp_dir, "buckets", bucket])
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

    test "includes CORS headers on list bucket requests", %{conn: conn, tmp_dir: tmp_dir} do
      bucket = "cors-list-bucket"

      bucket_path = Path.join([tmp_dir, "buckets", bucket])
      File.mkdir_p!(bucket_path)

      conn =
        conn
        |> put_req_header("origin", "https://example.com")
        |> get("/#{bucket}")

      assert get_resp_header(conn, "access-control-allow-origin") != []
    end
  end
end
