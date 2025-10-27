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

  alias AttackBlob.Release.CLI

  @shortdoc "List all access keys and their buckets"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    CLI.list_keys()
  end
end
