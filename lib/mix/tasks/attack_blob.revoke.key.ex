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

  alias AttackBlob.Release.CLI

  @shortdoc "Revoke an access key"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    case args do
      [access_key_id] ->
        # Use force: true to skip confirmation in development
        case CLI.revoke_key(access_key_id, force: true) do
          {:ok, _} -> :ok
          {:error, reason} -> Mix.raise(reason)
        end

      _ ->
        Mix.raise("Usage: mix attack_blob.revoke.key ACCESS_KEY_ID")
    end
  end
end
