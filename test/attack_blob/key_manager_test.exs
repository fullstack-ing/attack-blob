defmodule AttackBlob.KeyManagerTest do
  use ExUnit.Case, async: true

  alias AttackBlob.KeyManager

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "key_manager_test_#{:rand.uniform(1_000_000)}")
    keys_dir = Path.join(tmp_dir, "keys")
    File.mkdir_p!(keys_dir)

    # Generate unique name for this test's KeyManager instance
    unique_name = :"key_manager_#{:rand.uniform(1_000_000)}"

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir, keys_dir: keys_dir, unique_name: unique_name}
  end

  describe "start_link/1" do
    test "starts successfully with empty keys directory", %{tmp_dir: tmp_dir, unique_name: name} do
      assert {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert Process.alive?(pid)
      assert KeyManager.count(pid) == 0
    end

    test "loads existing keys on startup", %{
      keys_dir: keys_dir,
      tmp_dir: tmp_dir,
      unique_name: name
    } do
      # Create some test keys
      create_test_key(keys_dir, "AKIATEST1", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIATEST2", "secret2", "bucket2")

      assert {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 2
    end

    test "handles missing keys directory gracefully", %{tmp_dir: tmp_dir, unique_name: name} do
      # Don't create keys directory
      File.rm_rf!(Path.join(tmp_dir, "keys"))

      assert {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert Process.alive?(pid)
      assert KeyManager.count(pid) == 0
    end

    test "ignores non-JSON files", %{keys_dir: keys_dir, tmp_dir: tmp_dir, unique_name: name} do
      # Create valid key
      create_test_key(keys_dir, "AKIAVALID", "secret1", "bucket1")

      # Create non-JSON file
      txt_path = Path.join(keys_dir, "readme.txt")
      File.write!(txt_path, "some text")

      assert {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      # Should only load the .json file
      assert KeyManager.count(pid) == 1
    end
  end

  describe "lookup/2" do
    test "returns key when found", %{keys_dir: keys_dir, tmp_dir: tmp_dir, unique_name: name} do
      create_test_key(keys_dir, "AKIATEST", "my-secret", "my-bucket")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      assert {:ok, key} = KeyManager.lookup("AKIATEST", pid)
      assert key.access_key_id == "AKIATEST"
      assert key.secret_key == "my-secret"
      assert key.bucket == "my-bucket"
      assert key.permissions == ["put", "delete"]
    end

    test "returns error when key not found", %{tmp_dir: tmp_dir, unique_name: name} do
      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      assert KeyManager.lookup("NONEXISTENT", pid) == :error
    end

    test "can lookup multiple different keys", %{
      keys_dir: keys_dir,
      tmp_dir: tmp_dir,
      unique_name: name
    } do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")
      create_test_key(keys_dir, "AKIA003", "secret3", "bucket3")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      assert {:ok, key1} = KeyManager.lookup("AKIA001", pid)
      assert key1.bucket == "bucket1"

      assert {:ok, key2} = KeyManager.lookup("AKIA002", pid)
      assert key2.bucket == "bucket2"

      assert {:ok, key3} = KeyManager.lookup("AKIA003", pid)
      assert key3.bucket == "bucket3"
    end
  end

  describe "list_keys/1" do
    test "returns empty list when no keys loaded", %{tmp_dir: tmp_dir, unique_name: name} do
      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      assert KeyManager.list_keys(pid) == []
    end

    test "returns all loaded keys", %{keys_dir: keys_dir, tmp_dir: tmp_dir, unique_name: name} do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      keys = KeyManager.list_keys(pid)
      assert length(keys) == 2

      access_key_ids = Enum.map(keys, & &1.access_key_id) |> Enum.sort()
      assert access_key_ids == ["AKIA001", "AKIA002"]
    end

    test "keys contain all expected fields", %{
      keys_dir: keys_dir,
      tmp_dir: tmp_dir,
      unique_name: name
    } do
      create_test_key(keys_dir, "AKIATEST", "my-secret", "my-bucket")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      [key] = KeyManager.list_keys(pid)

      assert key.access_key_id
      assert key.secret_key
      assert key.bucket
      assert key.created_at
      assert key.permissions
    end
  end

  describe "reload/1" do
    test "loads newly added keys", %{keys_dir: keys_dir, tmp_dir: tmp_dir, unique_name: name} do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 1

      # Add new key
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")

      # Reload
      assert :ok = KeyManager.reload(pid)
      assert KeyManager.count(pid) == 2

      # Verify new key is accessible
      assert {:ok, _key} = KeyManager.lookup("AKIA002", pid)
    end

    test "removes deleted keys", %{keys_dir: keys_dir, tmp_dir: tmp_dir, unique_name: name} do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 2

      # Delete one key file
      File.rm!(Path.join(keys_dir, "AKIA001.json"))

      # Reload
      assert :ok = KeyManager.reload(pid)
      assert KeyManager.count(pid) == 1

      # Verify deleted key is no longer accessible
      assert KeyManager.lookup("AKIA001", pid) == :error
      assert {:ok, _key} = KeyManager.lookup("AKIA002", pid)
    end

    test "handles empty directory after reload", %{
      keys_dir: keys_dir,
      tmp_dir: tmp_dir,
      unique_name: name
    } do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 1

      # Delete all keys
      File.rm!(Path.join(keys_dir, "AKIA001.json"))

      # Reload
      assert :ok = KeyManager.reload(pid)
      assert KeyManager.count(pid) == 0
    end
  end

  describe "count/1" do
    test "returns 0 for empty key store", %{tmp_dir: tmp_dir, unique_name: name} do
      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 0
    end

    test "returns correct count of loaded keys", %{
      keys_dir: keys_dir,
      tmp_dir: tmp_dir,
      unique_name: name
    } do
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      create_test_key(keys_dir, "AKIA002", "secret2", "bucket2")
      create_test_key(keys_dir, "AKIA003", "secret3", "bucket3")

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 3
    end

    test "updates after reload", %{keys_dir: keys_dir, tmp_dir: tmp_dir, unique_name: name} do
      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)
      assert KeyManager.count(pid) == 0

      # Add keys and reload
      create_test_key(keys_dir, "AKIA001", "secret1", "bucket1")
      KeyManager.reload(pid)

      assert KeyManager.count(pid) == 1
    end
  end

  describe "concurrent access" do
    test "multiple lookups can happen concurrently", %{
      keys_dir: keys_dir,
      tmp_dir: tmp_dir,
      unique_name: name
    } do
      # Create multiple keys
      for i <- 1..10 do
        create_test_key(
          keys_dir,
          "AKIA#{String.pad_leading("#{i}", 3, "0")}",
          "secret#{i}",
          "bucket#{i}"
        )
      end

      {:ok, pid} = KeyManager.start_link(data_dir: tmp_dir, name: name)

      # Perform concurrent lookups
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            access_key_id = "AKIA#{String.pad_leading("#{i}", 3, "0")}"
            KeyManager.lookup(access_key_id, pid)
          end)
        end

      results = Task.await_many(tasks, :infinity)

      # All lookups should succeed
      assert Enum.all?(results, fn
               {:ok, _key} -> true
               _ -> false
             end)
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
  end
end
