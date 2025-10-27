defmodule Mix.Tasks.AttackBlob.List.Keys do
  @moduledoc """
  Lists all access keys and their associated buckets.

  Displays all access keys stored in the data directory with their bucket
  assignments, creation dates, and permissions. Secret keys are never displayed
  for security reasons.

  ## Usage

      mix attack_blob.list.keys

  ## Example Output

      Access Keys:

      Access Key ID:   AKIAEXAMPLE12345678
      Bucket:          my-bucket
      Created:         2025-10-26T10:30:00Z
      Permissions:     put, delete

      Access Key ID:   AKIATEST9876543210XX
      Bucket:          public-assets
      Created:         2025-10-26T11:45:00Z
      Permissions:     put, delete

      Total: 2 keys
  """

  use Mix.Task

  @shortdoc "List all access keys and their buckets"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    list_keys()
  end

  defp list_keys do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    keys_dir = Path.join(data_dir, "keys")

    case load_all_keys(keys_dir) do
      [] ->
        Mix.shell().info("""

        No access keys found.

        Create a new access key with: mix attack_blob.gen.key BUCKET_NAME
        """)

      keys ->
        display_keys(keys)
    end
  end

  defp load_all_keys(keys_dir) do
    case File.ls(keys_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&Path.join(keys_dir, &1))
        |> Enum.map(&load_key_file/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.created_at, :desc)

      {:error, :enoent} ->
        []
    end
  end

  defp load_key_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} -> data
          {:error, _} -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp display_keys(keys) do
    Mix.shell().info("\nAccess Keys:\n")

    Enum.each(keys, fn key ->
      Mix.shell().info("""
      Access Key ID:   #{key.access_key_id}
      Bucket:          #{key.bucket}
      Created:         #{key.created_at}
      Permissions:     #{Enum.join(key.permissions, ", ")}
      """)
    end)

    Mix.shell().info("Total: #{length(keys)} #{pluralize("key", length(keys))}")
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"
end
