defmodule Mix.Tasks.AttackBlob.List.Buckets do
  @moduledoc """
  Lists all buckets with their statistics.

  Displays all buckets in the data directory with object counts, total sizes,
  and the number of access keys that have permissions for each bucket.

  ## Usage

      mix attack_blob.list.buckets

  ## Example Output

      Buckets:

      Bucket:          my-bucket
      Objects:         42
      Total Size:      1.2 MB
      Access Keys:     2

      Bucket:          public-assets
      Objects:         128
      Total Size:      15.8 MB
      Access Keys:     1

      Total: 2 buckets
  """

  use Mix.Task

  @shortdoc "List all buckets with statistics"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    list_buckets()
  end

  defp list_buckets do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    buckets_dir = Path.join(data_dir, "buckets")
    keys_dir = Path.join(data_dir, "keys")

    case load_all_buckets(buckets_dir) do
      [] ->
        Mix.shell().info("""

        No buckets found.

        Create a new bucket with: mix attack_blob.gen.key BUCKET_NAME
        """)

      buckets ->
        # Load keys to count access keys per bucket
        keys = load_all_keys(keys_dir)
        display_buckets(buckets, keys)
    end
  end

  defp load_all_buckets(buckets_dir) do
    case File.ls(buckets_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          path = Path.join(buckets_dir, entry)
          File.dir?(path)
        end)
        |> Enum.map(fn bucket_name ->
          bucket_path = Path.join(buckets_dir, bucket_name)
          {object_count, total_size} = calculate_bucket_stats(bucket_path)

          %{
            name: bucket_name,
            path: bucket_path,
            object_count: object_count,
            total_size: total_size
          }
        end)
        |> Enum.sort_by(& &1.name)

      {:error, :enoent} ->
        []
    end
  end

  defp calculate_bucket_stats(bucket_path) do
    case list_all_files(bucket_path) do
      [] ->
        {0, 0}

      files ->
        total_size =
          files
          |> Enum.map(fn file_path ->
            case File.stat(file_path) do
              {:ok, %{size: size}} -> size
              _ -> 0
            end
          end)
          |> Enum.sum()

        {length(files), total_size}
    end
  end

  defp list_all_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full_path = Path.join(dir, entry)

          cond do
            File.regular?(full_path) -> [full_path]
            File.dir?(full_path) -> list_all_files(full_path)
            true -> []
          end
        end)

      {:error, _} ->
        []
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

  defp display_buckets(buckets, keys) do
    Mix.shell().info("\nBuckets:\n")

    Enum.each(buckets, fn bucket ->
      # Count how many keys have access to this bucket
      key_count = Enum.count(keys, fn key -> key.bucket == bucket.name end)

      Mix.shell().info("""
      Bucket:          #{bucket.name}
      Objects:         #{bucket.object_count}
      Total Size:      #{format_size(bucket.total_size)}
      Access Keys:     #{key_count}
      """)
    end)

    Mix.shell().info("Total: #{length(buckets)} #{pluralize("bucket", length(buckets))}")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_size(bytes),
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"
end
