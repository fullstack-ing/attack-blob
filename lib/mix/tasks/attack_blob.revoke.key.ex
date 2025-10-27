defmodule Mix.Tasks.AttackBlob.Revoke.Key do
  @moduledoc """
  Revokes an access key by deleting it from the system.

  Removes the access key file from disk, preventing further use of the key.
  If the KeyManager GenServer is running, it will need to be reloaded to
  reflect the change.

  ## Usage

      mix attack_blob.revoke.key ACCESS_KEY_ID

  ## Examples

      mix attack_blob.revoke.key AKIAEXAMPLE12345678

  ## Important

  This operation cannot be undone. Once a key is revoked, any clients using
  that key will no longer be able to upload or delete objects.
  """

  use Mix.Task

  @shortdoc "Revoke an access key"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    case args do
      [access_key_id] ->
        revoke_key(access_key_id)

      _ ->
        Mix.raise("Usage: mix attack_blob.revoke.key ACCESS_KEY_ID")
    end
  end

  defp revoke_key(access_key_id) do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    keys_dir = Path.join(data_dir, "keys")
    key_file_path = Path.join(keys_dir, "#{access_key_id}.json")

    case File.stat(key_file_path) do
      {:ok, _} ->
        # Load key info before deleting for confirmation message
        key_info = load_key_info(key_file_path)
        do_revoke_key(key_file_path, access_key_id, key_info)

      {:error, :enoent} ->
        Mix.raise("""
        Access key not found: #{access_key_id}

        Use 'mix attack_blob.list.keys' to see all available keys.
        """)

      {:error, reason} ->
        Mix.raise("Error accessing key file: #{inspect(reason)}")
    end
  end

  defp load_key_info(key_file_path) do
    case File.read(key_file_path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} -> data
          {:error, _} -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp do_revoke_key(key_file_path, access_key_id, key_info) do
    case File.rm(key_file_path) do
      :ok ->
        display_success_message(access_key_id, key_info)
        maybe_reload_key_manager()

      {:error, reason} ->
        Mix.raise("Failed to delete key file: #{inspect(reason)}")
    end
  end

  defp display_success_message(access_key_id, nil) do
    Mix.shell().info("""

    ✓ Access key revoked successfully!

    Access Key ID:   #{access_key_id}

    The key file has been deleted and the key can no longer be used.
    """)
  end

  defp display_success_message(access_key_id, %{bucket: bucket}) do
    Mix.shell().info("""

    ✓ Access key revoked successfully!

    Access Key ID:   #{access_key_id}
    Bucket:          #{bucket}

    The key file has been deleted and the key can no longer be used.
    """)
  end

  defp display_success_message(access_key_id, _key_info) do
    # Fallback for key_info that exists but doesn't have a bucket field
    Mix.shell().info("""

    ✓ Access key revoked successfully!

    Access Key ID:   #{access_key_id}

    The key file has been deleted and the key can no longer be used.
    """)
  end

  defp maybe_reload_key_manager do
    # Try to reload the KeyManager if it's running
    # This is best-effort - if the server isn't running, we just skip it
    try do
      case Process.whereis(AttackBlob.KeyManager) do
        nil ->
          Mix.shell().info("""
          Note: KeyManager is not running. If you start the application,
          it will automatically load the updated key list.
          """)

        pid when is_pid(pid) ->
          case AttackBlob.KeyManager.reload() do
            :ok ->
              Mix.shell().info("""
              KeyManager has been reloaded with the updated key list.
              """)

            _ ->
              Mix.shell().info("""
              Note: Could not reload KeyManager. Restart the application
              to ensure the changes take effect.
              """)
          end
      end
    rescue
      _ ->
        # If anything goes wrong, just skip the reload
        # The key file has been deleted, which is what matters
        :ok
    end
  end
end
