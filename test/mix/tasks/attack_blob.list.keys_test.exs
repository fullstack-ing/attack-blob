defmodule Mix.Tasks.AttackBlob.List.KeysTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.AttackBlob.List.Keys

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "list_keys_test_#{:rand.uniform(1_000_000)}")
    keys_dir = Path.join(tmp_dir, "keys")
    File.mkdir_p!(keys_dir)

    # Configure the app to use the temp directory
    original_data_dir = Application.get_env(:attack_blob, :data_dir)
    Application.put_env(:attack_blob, :data_dir, tmp_dir)

    on_exit(fn ->
      # Restore original config and clean up
      if original_data_dir do
        Application.put_env(:attack_blob, :data_dir, original_data_dir)
      else
        Application.delete_env(:attack_blob, :data_dir)
      end

      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir, keys_dir: keys_dir}
  end

  describe "run/1" do
    test "displays message when no keys exist" do
      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "No access keys found"
      assert output =~ "mix attack_blob.gen.key"
    end

    test "displays message when keys directory does not exist", %{tmp_dir: tmp_dir} do
      # Delete the keys directory
      File.rm_rf!(Path.join(tmp_dir, "keys"))

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "No access keys found"
    end

    test "lists single key with correct information", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIATEST123", "secret123", "my-bucket")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "Access Keys:"
      assert output =~ "Access Key ID:   AKIATEST123"
      assert output =~ "Bucket:          my-bucket"
      assert output =~ "Permissions:     put, delete"
      assert output =~ "Total: 1 key"
    end

    test "lists multiple keys with correct information", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")
      create_test_key(keys_dir, "AKIA003", "secret3", "bucket3")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "AKIA001"
      assert output =~ "bucket1"
      assert output =~ "AKIA002"
      assert output =~ "bucket2"
      assert output =~ "AKIA003"
      assert output =~ "bucket3"
      assert output =~ "Total: 3 keys"
    end

    test "does not display secret keys", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIATEST", "my-super-secret-key-12345", "bucket")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      refute output =~ "my-super-secret-key-12345"
      refute output =~ "Secret Key"
    end

    test "displays created_at timestamp", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIATEST", "secret", "bucket")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "Created:"
      # Should contain ISO8601 formatted timestamp
      assert output =~ ~r/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    end

    test "sorts keys by creation date (newest first)", %{keys_dir: keys_dir} do
      # Create keys with different timestamps
      create_test_key_with_date(keys_dir, "AKIA001", "secret1", "bucket1", "2025-10-26T10:00:00Z")
      create_test_key_with_date(keys_dir, "AKIA002", "secret2", "bucket2", "2025-10-26T12:00:00Z")
      create_test_key_with_date(keys_dir, "AKIA003", "secret3", "bucket3", "2025-10-26T11:00:00Z")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      # Extract the order of access key IDs in the output
      lines = String.split(output, "\n")

      akia001_line = Enum.find_index(lines, &String.contains?(&1, "AKIA001"))
      akia002_line = Enum.find_index(lines, &String.contains?(&1, "AKIA002"))
      akia003_line = Enum.find_index(lines, &String.contains?(&1, "AKIA003"))

      # Most recent (AKIA002 at 12:00) should appear first
      assert akia002_line < akia003_line
      assert akia003_line < akia001_line
    end

    test "displays 'key' for single key", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIATEST", "secret", "bucket")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "Total: 1 key"
      refute output =~ "1 keys"
    end

    test "displays 'keys' for multiple keys", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "Total: 2 keys"
    end

    test "ignores non-JSON files", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIAVALID", "secret", "bucket")

      # Create a non-JSON file
      txt_path = Path.join(keys_dir, "readme.txt")
      File.write!(txt_path, "some text")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      assert output =~ "AKIAVALID"
      assert output =~ "Total: 1 key"
    end

    test "handles corrupted JSON files gracefully", %{keys_dir: keys_dir} do
      # Create a valid key
      create_test_key(keys_dir, "AKIAVALID", "secret", "bucket")

      # Create a corrupted JSON file
      corrupted_path = Path.join(keys_dir, "AKIACORRUPT.json")
      File.write!(corrupted_path, "{invalid json content")

      output =
        capture_io(fn ->
          Keys.run([])
        end)

      # Should only list the valid key
      assert output =~ "AKIAVALID"
      refute output =~ "AKIACORRUPT"
      assert output =~ "Total: 1 key"
    end
  end

  ## Helper Functions

  defp create_test_key(keys_dir, access_key_id, secret_key, bucket) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    create_test_key_with_date(keys_dir, access_key_id, secret_key, bucket, timestamp)
  end

  defp create_test_key_with_date(keys_dir, access_key_id, secret_key, bucket, created_at) do
    key_data = %{
      access_key_id: access_key_id,
      secret_key: secret_key,
      bucket: bucket,
      created_at: created_at,
      permissions: ["put", "delete"]
    }

    path = Path.join(keys_dir, "#{access_key_id}.json")
    File.write!(path, Jason.encode!(key_data, pretty: true))
  end
end
