defmodule AttackBlob.Release.CLI do
  @moduledoc """
  Release-compatible CLI commands for AttackBlob operations.

  These functions can be called from both mix tasks (development) and
  release scripts (production). They return structured data and accept
  an IO device for output.
  """

  alias AttackBlob.KeyManager

  @bucket_name_regex ~r/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/

  @doc """
  Generates a new access key for the specified bucket.

  ## Options
  - `:data_dir` - Override the data directory (default: from application config)
  - `:io_device` - IO device for output (default: :stdio)

  ## Returns
  - `{:ok, %{access_key_id: string, secret_key: string, bucket: string}}`
  - `{:error, reason}`
  """
  def gen_key(bucket_name, opts \\ []) do
    io_device = Keyword.get(opts, :io_device, :stdio)
    data_dir = Keyword.get(opts, :data_dir, Application.get_env(:attack_blob, :data_dir, "./data"))

    with :ok <- validate_bucket_name(bucket_name),
         {:ok, bucket_path} <- create_bucket_directory(data_dir, bucket_name),
         {:ok, keys_dir} <- ensure_keys_directory(data_dir),
         {:ok, key_data} <- generate_key_data(bucket_name),
         {:ok, _key_file} <- write_key_file(keys_dir, key_data) do
      output_key_info(io_device, key_data, bucket_path)
      {:ok, key_data}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all access keys.

  ## Options
  - `:data_dir` - Override the data directory (default: from application config)
  - `:io_device` - IO device for output (default: :stdio)

  ## Returns
  - `{:ok, [key_info]}`
  """
  def list_keys(opts \\ []) do
    io_device = Keyword.get(opts, :io_device, :stdio)
    data_dir = Keyword.get(opts, :data_dir, Application.get_env(:attack_blob, :data_dir, "./data"))

    keys_dir = Path.join(data_dir, "keys")

    keys =
      if File.dir?(keys_dir) do
        keys_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&load_key_file(keys_dir, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.created_at, :desc)
      else
        []
      end

    output_keys_list(io_device, keys)
    {:ok, keys}
  end

  @doc """
  Lists all buckets with statistics.

  ## Options
  - `:data_dir` - Override the data directory (default: from application config)
  - `:io_device` - IO device for output (default: :stdio)

  ## Returns
  - `{:ok, [bucket_info]}`
  """
  def list_buckets(opts \\ []) do
    io_device = Keyword.get(opts, :io_device, :stdio)
    data_dir = Keyword.get(opts, :data_dir, Application.get_env(:attack_blob, :data_dir, "./data"))

    buckets_dir = Path.join(data_dir, "buckets")

    buckets =
      if File.dir?(buckets_dir) do
        buckets_dir
        |> File.ls!()
        |> Enum.map(&get_bucket_info(buckets_dir, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.name)
      else
        []
      end

    output_buckets_list(io_device, buckets)
    {:ok, buckets}
  end

  @doc """
  Revokes an access key.

  ## Options
  - `:data_dir` - Override the data directory (default: from application config)
  - `:io_device` - IO device for output (default: :stdio)
  - `:force` - Skip confirmation prompt (default: false)

  ## Returns
  - `{:ok, :revoked}`
  - `{:error, reason}`
  """
  def revoke_key(access_key_id, opts \\ []) do
    io_device = Keyword.get(opts, :io_device, :stdio)
    data_dir = Keyword.get(opts, :data_dir, Application.get_env(:attack_blob, :data_dir, "./data"))
    force = Keyword.get(opts, :force, false)

    keys_dir = Path.join(data_dir, "keys")
    key_file = Path.join(keys_dir, "#{access_key_id}.json")

    cond do
      not File.exists?(key_file) ->
        {:error,
         "Access key not found: #{access_key_id}\n\nUse 'mix attack_blob.list.keys' to see all available keys."}

      force or confirm_revocation(io_device, access_key_id) ->
        # Load key info before deleting for confirmation message
        key_info = load_key_file(keys_dir, "#{access_key_id}.json")

        case File.rm(key_file) do
          :ok ->
            reload_key_manager()

            IO.puts(io_device, "\nAccess key revoked successfully!")
            IO.puts(io_device, "")
            IO.puts(io_device, "Access Key ID:   #{access_key_id}")

            if key_info && key_info.bucket do
              IO.puts(io_device, "Bucket:          #{key_info.bucket}")
            end

            IO.puts(io_device, "")
            IO.puts(io_device, "The key file has been deleted and the key can no longer be used.")

            {:ok, :revoked}

          {:error, reason} ->
            {:error, "Failed to revoke key: #{inspect(reason)}"}
        end

      true ->
        IO.puts(io_device, "\nRevocation cancelled.")
        {:ok, :cancelled}
    end
  end

  ## Private Functions

  defp validate_bucket_name(bucket_name) do
    cond do
      byte_size(bucket_name) < 3 or byte_size(bucket_name) > 63 ->
        {:error, "Bucket name must be between 3 and 63 characters"}

      not Regex.match?(@bucket_name_regex, bucket_name) ->
        {:error,
         "Invalid bucket name. Must start and end with lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."}

      true ->
        :ok
    end
  end

  defp create_bucket_directory(data_dir, bucket_name) do
    bucket_path = Path.join([data_dir, "buckets", bucket_name])

    case File.mkdir_p(bucket_path) do
      :ok -> {:ok, bucket_path}
      {:error, reason} -> {:error, "Failed to create bucket directory: #{inspect(reason)}"}
    end
  end

  defp ensure_keys_directory(data_dir) do
    keys_dir = Path.join(data_dir, "keys")

    case File.mkdir_p(keys_dir) do
      :ok -> {:ok, keys_dir}
      {:error, reason} -> {:error, "Failed to create keys directory: #{inspect(reason)}"}
    end
  end

  defp generate_key_data(bucket_name) do
    access_key_id = generate_access_key_id()
    secret_key = generate_secret_key()

    key_data = %{
      access_key_id: access_key_id,
      secret_key: secret_key,
      bucket: bucket_name,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      permissions: ["put", "delete"]
    }

    {:ok, key_data}
  end

  defp generate_access_key_id do
    random_part =
      :crypto.strong_rand_bytes(12)
      |> Base.encode32(case: :upper, padding: false)
      |> binary_part(0, 16)

    "AKIA#{random_part}"
  end

  defp generate_secret_key do
    :crypto.strong_rand_bytes(30)
    |> Base.encode64(padding: false)
    |> binary_part(0, 40)
  end

  defp write_key_file(keys_dir, key_data) do
    key_file = Path.join(keys_dir, "#{key_data.access_key_id}.json")

    case File.write(key_file, Jason.encode!(key_data, pretty: true)) do
      :ok ->
        File.chmod(key_file, 0o600)
        {:ok, key_file}

      {:error, reason} ->
        {:error, "Failed to write key file: #{inspect(reason)}"}
    end
  end

  defp output_key_info(io_device, key_data, bucket_path) do
    IO.puts(io_device, "\nAccess key created successfully!")
    IO.puts(io_device, "")
    IO.puts(io_device, "Bucket: #{key_data.bucket}")
    IO.puts(io_device, "Bucket path: #{bucket_path}")
    IO.puts(io_device, "")
    IO.puts(io_device, "Access Key ID: #{key_data.access_key_id}")
    IO.puts(io_device, "Secret Key: #{key_data.secret_key}")
    IO.puts(io_device, "")
    IO.puts(io_device, "Permissions: #{Enum.join(key_data.permissions, ", ")}")
    IO.puts(io_device, "")

    IO.puts(
      io_device,
      "IMPORTANT: Save the secret key now! It won't be displayed again."
    )
  end

  defp load_key_file(keys_dir, filename) do
    key_path = Path.join(keys_dir, filename)

    case File.read(key_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            %{
              access_key_id: data["access_key_id"],
              bucket: data["bucket"],
              created_at: data["created_at"],
              permissions: data["permissions"] || []
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp output_keys_list(io_device, []) do
    IO.puts(io_device, "\nNo access keys found.")
    IO.puts(io_device, "")
    IO.puts(io_device, "Create a new access key with: mix attack_blob.gen.key BUCKET_NAME")
  end

  defp output_keys_list(io_device, keys) do
    IO.puts(io_device, "\nAccess Keys:\n")

    for key <- keys do
      IO.puts(io_device, "Access Key ID:   #{key.access_key_id}")
      IO.puts(io_device, "Bucket:          #{key.bucket}")
      IO.puts(io_device, "Created:         #{format_datetime(key.created_at)}")
      IO.puts(io_device, "Permissions:     #{Enum.join(key.permissions, ", ")}")
      IO.puts(io_device, "")
    end

    IO.puts(io_device, "Total: #{length(keys)} #{pluralize_key(length(keys))}")
  end

  defp pluralize_key(1), do: "key"
  defp pluralize_key(_), do: "keys"

  defp get_bucket_info(buckets_dir, bucket_name) do
    bucket_path = Path.join(buckets_dir, bucket_name)

    if File.dir?(bucket_path) do
      {object_count, total_size} = calculate_bucket_stats(bucket_path)

      %{
        name: bucket_name,
        path: bucket_path,
        object_count: object_count,
        total_size: total_size
      }
    else
      nil
    end
  end

  defp calculate_bucket_stats(bucket_path) do
    bucket_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.reduce({0, 0}, fn file, {count, size} ->
      file_size = File.stat!(file).size
      {count + 1, size + file_size}
    end)
  end

  defp output_buckets_list(io_device, []) do
    IO.puts(io_device, "\nNo buckets found.")
    IO.puts(io_device, "")
    IO.puts(io_device, "Create a new bucket with: mix attack_blob.gen.key BUCKET_NAME")
  end

  defp output_buckets_list(io_device, buckets) do
    # Load keys to count access keys per bucket
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    keys_dir = Path.join(data_dir, "keys")
    keys = load_all_keys_for_buckets(keys_dir)

    IO.puts(io_device, "\nBuckets:\n")

    for bucket <- buckets do
      # Count how many keys have access to this bucket
      key_count = Enum.count(keys, fn key -> key[:bucket] == bucket.name end)

      IO.puts(io_device, "Bucket:          #{bucket.name}")
      IO.puts(io_device, "Objects:         #{bucket.object_count}")
      IO.puts(io_device, "Total Size:      #{format_bytes(bucket.total_size)}")
      IO.puts(io_device, "Access Keys:     #{key_count}")
      IO.puts(io_device, "")
    end

    IO.puts(io_device, "Total: #{length(buckets)} #{pluralize_bucket(length(buckets))}")
  end

  defp pluralize_bucket(1), do: "bucket"
  defp pluralize_bucket(_), do: "buckets"

  defp load_all_keys_for_buckets(keys_dir) do
    case File.ls(keys_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&load_key_file(keys_dir, &1))
        |> Enum.reject(&is_nil/1)

      {:error, :enoent} ->
        []
    end
  end

  defp confirm_revocation(io_device, access_key_id) do
    IO.puts(io_device, "\nWARNING: This will permanently revoke the access key.")
    IO.puts(io_device, "Access Key ID: #{access_key_id}")
    IO.write(io_device, "\nAre you sure you want to continue? (y/N): ")

    case IO.gets(io_device, "") do
      input when is_binary(input) ->
        String.trim(input) |> String.downcase() == "y"

      _ ->
        false
    end
  end

  defp reload_key_manager do
    case Process.whereis(KeyManager) do
      nil -> :ok
      _pid -> KeyManager.reload()
    end
  end

  defp format_datetime(iso8601_string) when is_binary(iso8601_string) do
    # Return the ISO8601 string as-is (already in correct format)
    iso8601_string
  end

  defp format_datetime(_), do: "Unknown"

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 2)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"

  defp format_bytes(bytes),
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
end
