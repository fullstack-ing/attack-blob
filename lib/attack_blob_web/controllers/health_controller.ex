defmodule AttackBlobWeb.HealthController do
  use AttackBlobWeb, :controller

  @doc """
  GET /health - Health check endpoint

  Returns the application status and checks system components.
  """
  def check(conn, _params) do
    health_status = %{
      status: "healthy",
      checks: %{
        key_manager: check_key_manager(),
        data_directory: check_data_directory()
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    status_code = if all_checks_passing?(health_status), do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  defp check_key_manager do
    case Process.whereis(AttackBlob.KeyManager) do
      nil ->
        %{status: "unhealthy", message: "KeyManager not running"}

      pid when is_pid(pid) ->
        try do
          count = AttackBlob.KeyManager.count()
          %{status: "healthy", keys_loaded: count}
        rescue
          _ ->
            %{status: "unhealthy", message: "KeyManager not responding"}
        end
    end
  end

  defp check_data_directory do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")

    cond do
      !File.exists?(data_dir) ->
        %{status: "unhealthy", message: "Data directory does not exist", path: data_dir}

      !File.dir?(data_dir) ->
        %{status: "unhealthy", message: "Data directory path is not a directory", path: data_dir}

      true ->
        # Check if buckets and keys directories exist
        buckets_dir = Path.join(data_dir, "buckets")
        keys_dir = Path.join(data_dir, "keys")

        buckets_exist = File.dir?(buckets_dir)
        keys_exist = File.dir?(keys_dir)

        if buckets_exist and keys_exist do
          %{status: "healthy", path: data_dir}
        else
          %{
            status: "degraded",
            message: "Some subdirectories missing",
            path: data_dir,
            buckets_dir: buckets_exist,
            keys_dir: keys_exist
          }
        end
    end
  end

  defp all_checks_passing?(health_status) do
    Enum.all?(health_status.checks, fn {_name, check} ->
      check.status in ["healthy", "degraded"]
    end)
  end
end
