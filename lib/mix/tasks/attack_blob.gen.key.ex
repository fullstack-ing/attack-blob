defmodule Mix.Tasks.AttackBlob.Gen.Key do
  @moduledoc """
  Generates a new access key for a bucket.

  Creates the bucket directory if it doesn't exist and generates a new
  access key pair. The secret key is displayed ONCE and never shown again.

  ## Usage

      mix attack_blob.gen.key BUCKET_NAME

  ## Examples

      mix attack_blob.gen.key my-bucket
      mix attack_blob.gen.key public-assets

  ## Important

  The secret key is displayed only once during generation. Save it securely
  (e.g., in environment variables) as it cannot be retrieved later.
  """

  use Mix.Task

  @shortdoc "Generate a new access key for a bucket"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    case args do
      [bucket_name] ->
        generate_key(bucket_name)

      _ ->
        Mix.raise("Usage: mix attack_blob.gen.key BUCKET_NAME")
    end
  end

  defp generate_key(bucket_name) do
    with :ok <- validate_bucket_name(bucket_name) do
      do_generate_key(bucket_name)
    else
      {:error, :invalid_bucket_name} ->
        Mix.raise("""
        Invalid bucket name: #{bucket_name}

        Bucket names must:
        - Be 3-63 characters long
        - Contain only lowercase letters, numbers, and hyphens
        - Start and end with a letter or number
        """)
    end
  end

  defp validate_bucket_name(name) when byte_size(name) < 3, do: {:error, :invalid_bucket_name}
  defp validate_bucket_name(name) when byte_size(name) > 63, do: {:error, :invalid_bucket_name}

  defp validate_bucket_name(name) do
    case Regex.match?(~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/, name) do
      true -> :ok
      false -> {:error, :invalid_bucket_name}
    end
  end

  defp do_generate_key(bucket_name) do
    data_dir = Application.get_env(:attack_blob, :data_dir, "./data")
    buckets_dir = Path.join(data_dir, "buckets")
    keys_dir = Path.join(data_dir, "keys")
    bucket_path = Path.join(buckets_dir, bucket_name)

    # Create directories
    File.mkdir_p!(buckets_dir)
    File.mkdir_p!(keys_dir)
    File.mkdir_p!(bucket_path)

    # Generate access key ID and secret key
    access_key_id = generate_access_key_id()
    secret_key = generate_secret_key()

    # Create key file
    key_data = %{
      access_key_id: access_key_id,
      secret_key: secret_key,
      bucket: bucket_name,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      permissions: ["put", "delete"]
    }

    key_file_path = Path.join(keys_dir, "#{access_key_id}.json")
    json_content = Jason.encode!(key_data, pretty: true)

    # Write file
    File.write!(key_file_path, json_content)

    # Set restrictive file permissions (owner read/write only)
    File.chmod!(key_file_path, 0o600)

    # Display success message with credentials
    Mix.shell().info("""

    ✓ Access key created successfully!

    Bucket:          #{bucket_name}
    Access Key ID:   #{access_key_id}
    Secret Key:      #{secret_key}

    ⚠️  IMPORTANT: Save the secret key now! It will not be displayed again.

    The key file has been saved to: #{key_file_path}
    Bucket directory created at:   #{bucket_path}
    """)
  end

  defp generate_access_key_id do
    # Generate 20 character access key ID (similar to AWS format AKIA...)
    "AKIA" <> random_string(16, :alphanum_upper)
  end

  defp generate_secret_key do
    # Generate 40 character secret key (base64-like characters)
    random_string(40, :base64)
  end

  defp random_string(length, :alphanum_upper) do
    chars = Enum.to_list(?A..?Z) ++ Enum.to_list(?0..?9)
    generate_random_chars(length, chars)
  end

  defp random_string(length, :base64) do
    chars = Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9) ++ [?+, ?/]
    generate_random_chars(length, chars)
  end

  defp generate_random_chars(length, chars) do
    1..length
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> List.to_string()
  end
end
