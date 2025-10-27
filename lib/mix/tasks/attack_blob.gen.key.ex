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

  alias AttackBlob.Release.CLI

  @shortdoc "Generate a new access key for a bucket"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    case args do
      [bucket_name] ->
        case CLI.gen_key(bucket_name) do
          {:ok, _key_data} -> :ok
          {:error, reason} -> Mix.raise(reason)
        end

      _ ->
        Mix.raise("Usage: mix attack_blob.gen.key BUCKET_NAME")
    end
  end
end
