defmodule Mix.Tasks.AttackBlob.Revoke.KeyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.AttackBlob.Revoke.Key

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "revoke_key_test_#{:rand.uniform(1_000_000)}")
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
    test "successfully revokes existing key", %{keys_dir: keys_dir} do
      access_key_id = "AKIATEST12345"
      create_test_key(keys_dir, access_key_id, "secret123", "my-bucket")

      output =
        capture_io(fn ->
          Key.run([access_key_id])
        end)

      assert output =~ "Access key revoked successfully!"
      assert output =~ access_key_id
      assert output =~ "my-bucket"
    end

    test "deletes key file from disk", %{keys_dir: keys_dir} do
      access_key_id = "AKIATEST12345"
      key_file_path = create_test_key(keys_dir, access_key_id, "secret123", "my-bucket")

      # Verify file exists before revocation
      assert File.exists?(key_file_path)

      capture_io(fn ->
        Key.run([access_key_id])
      end)

      # Verify file is deleted after revocation
      refute File.exists?(key_file_path)
    end

    test "raises error when key does not exist" do
      assert_raise Mix.Error, ~r/Access key not found/, fn ->
        capture_io(fn ->
          Key.run(["AKIANONEXISTENT"])
        end)
      end
    end

    test "error message suggests using list.keys command" do
      error_message =
        try do
          capture_io(fn ->
            Key.run(["AKIANONEXISTENT"])
          end)
        rescue
          e in Mix.Error -> e.message
        end

      assert error_message =~ "mix attack_blob.list.keys"
    end

    test "shows usage when no arguments provided" do
      assert_raise Mix.Error, ~r/Usage:/, fn ->
        capture_io(fn ->
          Key.run([])
        end)
      end
    end

    test "shows usage when too many arguments provided" do
      assert_raise Mix.Error, ~r/Usage:/, fn ->
        capture_io(fn ->
          Key.run(["AKIA001", "AKIA002"])
        end)
      end
    end

    test "displays confirmation without bucket info for corrupted key file", %{keys_dir: keys_dir} do
      access_key_id = "AKIACORRUPT"
      key_file_path = Path.join(keys_dir, "#{access_key_id}.json")

      # Create a corrupted JSON file
      File.write!(key_file_path, "{invalid json}")

      output =
        capture_io(fn ->
          Key.run([access_key_id])
        end)

      assert output =~ "Access key revoked successfully!"
      assert output =~ access_key_id
      # Should not crash, even though bucket info isn't available
      refute output =~ "Bucket:"
    end

    test "handles key files with missing bucket field", %{keys_dir: keys_dir} do
      access_key_id = "AKIAINCOMPLETE"
      key_file_path = Path.join(keys_dir, "#{access_key_id}.json")

      # Create key file missing bucket field
      incomplete_data = %{
        access_key_id: access_key_id,
        secret_key: "secret123"
      }

      File.write!(key_file_path, Jason.encode!(incomplete_data))

      # Should not crash
      output =
        capture_io(fn ->
          Key.run([access_key_id])
        end)

      assert output =~ "Access key revoked successfully!"
    end

    test "removes key from multiple keys without affecting others", %{keys_dir: keys_dir} do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")
      create_test_key(keys_dir, "AKIA003", "secret3", "bucket3")

      # Verify all 3 keys exist
      assert length(File.ls!(keys_dir)) == 3

      # Revoke one key
      capture_io(fn ->
        Key.run(["AKIA002"])
      end)

      # Verify only 2 keys remain
      remaining_files = File.ls!(keys_dir)
      assert length(remaining_files) == 2

      # Verify the correct keys remain
      assert "AKIA001.json" in remaining_files
      assert "AKIA003.json" in remaining_files
      refute "AKIA002.json" in remaining_files
    end

    test "output includes warning about deleted key", %{keys_dir: keys_dir} do
      access_key_id = "AKIATEST"
      create_test_key(keys_dir, access_key_id, "secret", "bucket")

      output =
        capture_io(fn ->
          Key.run([access_key_id])
        end)

      assert output =~ "key can no longer be used" or output =~ "deleted"
    end
  end

  ## Helper Functions

  defp create_test_key(keys_dir, access_key_id, secret_key, bucket) do
    key_data = %{
      access_key_id: access_key_id,
      secret_key: secret_key,
      bucket: bucket,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      permissions: ["put", "delete"]
    }

    path = Path.join(keys_dir, "#{access_key_id}.json")
    File.write!(path, Jason.encode!(key_data, pretty: true))
    path
  end
end
