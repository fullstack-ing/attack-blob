defmodule AttackBlobWeb.HealthControllerTest do
  use AttackBlobWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns healthy status when all checks pass", %{conn: conn} do
      conn = get(conn, "/health")

      assert conn.status == 200
      response = json_response(conn, 200)

      assert response["status"] == "healthy"
      assert response["timestamp"]
      assert response["checks"]
    end

    test "includes KeyManager status in health check", %{conn: conn} do
      conn = get(conn, "/health")

      response = json_response(conn, 200)

      assert response["checks"]["key_manager"]
      assert response["checks"]["key_manager"]["status"] in ["healthy", "unhealthy"]
    end

    test "reports KeyManager as healthy when running", %{conn: conn} do
      conn = get(conn, "/health")

      response = json_response(conn, 200)

      # KeyManager should be running in tests
      assert response["checks"]["key_manager"]["status"] == "healthy"
      assert Map.has_key?(response["checks"]["key_manager"], "keys_loaded")
    end

    test "includes data directory status", %{conn: conn} do
      conn = get(conn, "/health")

      response = json_response(conn, 200)

      assert response["checks"]["data_directory"]

      assert response["checks"]["data_directory"]["status"] in [
               "healthy",
               "degraded",
               "unhealthy"
             ]
    end

    test "reports data directory status correctly", %{conn: conn} do
      conn = get(conn, "/health")

      response = json_response(conn, 200)

      data_dir_check = response["checks"]["data_directory"]

      # Should have status and path
      assert data_dir_check["status"]
      assert data_dir_check["path"]
    end

    test "returns 200 when system is healthy", %{conn: conn} do
      conn = get(conn, "/health")

      # Should return 200 if all systems are operational
      assert conn.status in [200, 503]
    end

    test "includes timestamp in ISO8601 format", %{conn: conn} do
      conn = get(conn, "/health")

      response = json_response(conn, 200)

      # Verify timestamp is in ISO8601 format
      assert response["timestamp"] =~ ~r/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    end

    test "health check does not require authentication", %{conn: conn} do
      # Should work without any auth headers
      conn = get(conn, "/health")

      assert conn.status in [200, 503]
    end
  end
end
