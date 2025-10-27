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

  alias AttackBlob.Release.CLI

  @shortdoc "List all buckets with statistics"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    CLI.list_buckets()
  end
end
