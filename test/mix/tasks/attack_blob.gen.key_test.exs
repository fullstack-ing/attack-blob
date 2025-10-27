defmodule Mix.Tasks.AttackBlob.Gen.KeyTest do
  use ExUnit.Case, async: true

  import Bitwise
  import ExUnit.CaptureIO

  alias Mix.Tasks.AttackBlob.Gen.Key

  @test_bucket "test-bucket"

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "attack_blob_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

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

    %{tmp_dir: tmp_dir}
  end

  describe "run/1" do
    test "creates bucket directory and key file", %{tmp_dir: tmp_dir} do
      capture_io(fn ->
        Key.run([@test_bucket])
      end)

      # Check bucket directory was created
      bucket_path = Path.join([tmp_dir, "buckets", @test_bucket])
      assert File.dir?(bucket_path)

      # Check keys directory was created
      keys_dir = Path.join(tmp_dir, "keys")
      assert File.dir?(keys_dir)

      # Check that a key file was created
      key_files = File.ls!(keys_dir)
      assert length(key_files) == 1
    end

    test "generates valid access key ID and secret key", %{tmp_dir: tmp_dir} do
      capture_io(fn ->
        Key.run([@test_bucket])
      end)

      keys_dir = Path.join(tmp_dir, "keys")
      [key_file] = File.ls!(keys_dir)

      # Read and parse the key file
      key_path = Path.join(keys_dir, key_file)
      key_data = File.read!(key_path) |> Jason.decode!()

      # Verify access key ID format (AKIA + 16 chars)
      assert String.starts_with?(key_data["access_key_id"], "AKIA")
      assert String.length(key_data["access_key_id"]) == 20

      # Verify secret key format (40 characters)
      assert String.length(key_data["secret_key"]) == 40

      # Verify bucket name
      assert key_data["bucket"] == @test_bucket

      # Verify permissions
      assert key_data["permissions"] == ["put", "delete"]

      # Verify created_at is present
      assert key_data["created_at"]
    end

    test "sets restrictive file permissions on key file", %{tmp_dir: tmp_dir} do
      capture_io(fn ->
        Key.run([@test_bucket])
      end)

      keys_dir = Path.join(tmp_dir, "keys")
      [key_file] = File.ls!(keys_dir)
      key_path = Path.join(keys_dir, key_file)

      # Check file permissions (0600 = owner read/write only)
      %{mode: mode} = File.stat!(key_path)
      # Extract permission bits (last 9 bits)
      permissions = mode &&& 0o777
      assert permissions == 0o600
    end

    test "displays secret key in output" do
      output =
        capture_io(fn ->
          Key.run([@test_bucket])
        end)

      assert output =~ "Access key created successfully!"
      assert output =~ "Bucket:"
      assert output =~ @test_bucket
      assert output =~ "Access Key ID:"
      assert output =~ "AKIA"
      assert output =~ "Secret Key:"
      assert output =~ "IMPORTANT: Save the secret key now!"
    end

    test "rejects invalid bucket names" do
      invalid_names = [
        "AB",
        # too short
        "invalid_bucket",
        # underscore not allowed
        "Invalid",
        # uppercase not allowed
        "bucket-",
        # can't end with hyphen
        "-bucket",
        # can't start with hyphen
        String.duplicate("a", 64)
        # too long
      ]

      for invalid_name <- invalid_names do
        assert_raise Mix.Error, fn ->
          capture_io(fn ->
            Key.run([invalid_name])
          end)
        end
      end
    end

    test "accepts valid bucket names" do
      valid_names = ["abc", "my-bucket", "bucket123", "a1-b2-c3"]

      for valid_name <- valid_names do
        # Should not raise
        capture_io(fn ->
          Key.run([valid_name])
        end)
      end
    end

    test "shows usage when no arguments provided" do
      assert_raise Mix.Error, fn ->
        capture_io(fn ->
          Key.run([])
        end)
      end
    end

    test "shows usage when too many arguments provided" do
      assert_raise Mix.Error, fn ->
        capture_io(fn ->
          Key.run(["bucket1", "bucket2"])
        end)
      end
    end

    test "generates unique keys for multiple runs", %{tmp_dir: tmp_dir} do
      # Generate first key
      capture_io(fn ->
        Key.run([@test_bucket])
      end)

      # Generate second key
      capture_io(fn ->
        Key.run([@test_bucket])
      end)

      keys_dir = Path.join(tmp_dir, "keys")
      key_files = File.ls!(keys_dir)

      # Should have 2 different key files
      assert length(key_files) == 2

      # Read both keys and verify they're different
      [key1_path, key2_path] = Enum.map(key_files, &Path.join(keys_dir, &1))

      key1 = File.read!(key1_path) |> Jason.decode!()
      key2 = File.read!(key2_path) |> Jason.decode!()

      assert key1["access_key_id"] != key2["access_key_id"]
      assert key1["secret_key"] != key2["secret_key"]
    end
  end
end
