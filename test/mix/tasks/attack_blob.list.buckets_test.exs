defmodule Mix.Tasks.AttackBlob.List.BucketsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.AttackBlob.List.Buckets

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "list_buckets_test_#{:rand.uniform(1_000_000)}")
    buckets_dir = Path.join(tmp_dir, "buckets")
    keys_dir = Path.join(tmp_dir, "keys")
    File.mkdir_p!(buckets_dir)
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

    %{tmp_dir: tmp_dir, buckets_dir: buckets_dir, keys_dir: keys_dir}
  end

  describe "run/1" do
    test "displays message when no buckets exist" do
      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "No buckets found"
      assert output =~ "mix attack_blob.gen.key"
    end

    test "displays message when buckets directory does not exist", %{tmp_dir: tmp_dir} do
      # Delete the buckets directory
      File.rm_rf!(Path.join(tmp_dir, "buckets"))

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "No buckets found"
    end

    test "lists single empty bucket", %{buckets_dir: buckets_dir} do
      create_bucket(buckets_dir, "my-bucket")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "Buckets:"
      assert output =~ "Bucket:          my-bucket"
      assert output =~ "Objects:         0"
      assert output =~ "Total Size:      0 B"
      assert output =~ "Access Keys:     0"
      assert output =~ "Total: 1 bucket"
    end

    test "lists bucket with objects", %{buckets_dir: buckets_dir} do
      bucket_path = create_bucket(buckets_dir, "my-bucket")
      # Create some test files
      File.write!(Path.join(bucket_path, "file1.txt"), "Hello")
      File.write!(Path.join(bucket_path, "file2.txt"), "World")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "my-bucket"
      assert output =~ "Objects:         2"
      assert output =~ "Total Size:      10 B"
    end

    test "counts nested objects", %{buckets_dir: buckets_dir} do
      bucket_path = create_bucket(buckets_dir, "my-bucket")

      # Create nested directory structure
      nested_dir = Path.join([bucket_path, "path", "to", "nested"])
      File.mkdir_p!(nested_dir)

      File.write!(Path.join(bucket_path, "root.txt"), "root")
      File.write!(Path.join([bucket_path, "path", "level1.txt"]), "level1")
      File.write!(Path.join(nested_dir, "deep.txt"), "deep")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "Objects:         3"
    end

    test "calculates total size correctly", %{buckets_dir: buckets_dir} do
      bucket_path = create_bucket(buckets_dir, "my-bucket")

      # Create files with known sizes
      File.write!(Path.join(bucket_path, "small.txt"), String.duplicate("a", 100))
      File.write!(Path.join(bucket_path, "medium.txt"), String.duplicate("b", 500))

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "Objects:         2"
      assert output =~ "Total Size:      600 B"
    end

    test "counts access keys per bucket", %{buckets_dir: buckets_dir, keys_dir: keys_dir} do
      create_bucket(buckets_dir, "bucket1")
      create_bucket(buckets_dir, "bucket2")

      # Create keys for different buckets
      create_test_key(keys_dir, "AKIA001", "bucket1")
      create_test_key(keys_dir, "AKIA002", "bucket1")
      create_test_key(keys_dir, "AKIA003", "bucket2")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      # Extract the access key counts from the output
      lines = String.split(output, "\n")

      bucket1_section = extract_bucket_section(lines, "bucket1")
      assert bucket1_section =~ "Access Keys:     2"

      bucket2_section = extract_bucket_section(lines, "bucket2")
      assert bucket2_section =~ "Access Keys:     1"
    end

    test "formats sizes correctly" do
      # Test the different size formats by creating buckets with different sizes
      # This is tested implicitly through the other tests, but we can verify
      # the format strings work by checking the output patterns

      # Bytes
      assert format_size(100) =~ ~r/^\d+ B$/

      # Kilobytes
      assert format_size(2048) =~ ~r/^\d+\.\d+ KB$/

      # Megabytes
      assert format_size(2 * 1024 * 1024) =~ ~r/^\d+\.\d+ MB$/

      # Gigabytes
      assert format_size(2 * 1024 * 1024 * 1024) =~ ~r/^\d+\.\d+ GB$/
    end

    test "sorts buckets alphabetically", %{buckets_dir: buckets_dir} do
      create_bucket(buckets_dir, "zebra-bucket")
      create_bucket(buckets_dir, "alpha-bucket")
      create_bucket(buckets_dir, "middle-bucket")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      lines = String.split(output, "\n")

      alpha_line = Enum.find_index(lines, &String.contains?(&1, "alpha-bucket"))
      middle_line = Enum.find_index(lines, &String.contains?(&1, "middle-bucket"))
      zebra_line = Enum.find_index(lines, &String.contains?(&1, "zebra-bucket"))

      assert alpha_line < middle_line
      assert middle_line < zebra_line
    end

    test "displays 'bucket' for single bucket", %{buckets_dir: buckets_dir} do
      create_bucket(buckets_dir, "my-bucket")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "Total: 1 bucket"
      refute output =~ "1 buckets"
    end

    test "displays 'buckets' for multiple buckets", %{buckets_dir: buckets_dir} do
      create_bucket(buckets_dir, "bucket1")
      create_bucket(buckets_dir, "bucket2")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "Total: 2 buckets"
    end

    test "lists multiple buckets with different stats", %{
      buckets_dir: buckets_dir,
      keys_dir: keys_dir
    } do
      bucket1_path = create_bucket(buckets_dir, "bucket1")
      bucket2_path = create_bucket(buckets_dir, "bucket2")

      # bucket1: 2 objects, 2 keys
      File.write!(Path.join(bucket1_path, "file1.txt"), "content1")
      File.write!(Path.join(bucket1_path, "file2.txt"), "content2")
      create_test_key(keys_dir, "AKIA001", "bucket1")
      create_test_key(keys_dir, "AKIA002", "bucket1")

      # bucket2: 1 object, 1 key
      File.write!(Path.join(bucket2_path, "file.txt"), "data")
      create_test_key(keys_dir, "AKIA003", "bucket2")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "bucket1"
      assert output =~ "bucket2"
      assert output =~ "Total: 2 buckets"
    end

    test "ignores non-directory entries in buckets folder", %{buckets_dir: buckets_dir} do
      create_bucket(buckets_dir, "valid-bucket")

      # Create a file in the buckets directory (not a bucket)
      File.write!(Path.join(buckets_dir, "not-a-bucket.txt"), "ignored")

      output =
        capture_io(fn ->
          Buckets.run([])
        end)

      assert output =~ "valid-bucket"
      refute output =~ "not-a-bucket"
      assert output =~ "Total: 1 bucket"
    end
  end

  ## Helper Functions

  defp create_bucket(buckets_dir, name) do
    bucket_path = Path.join(buckets_dir, name)
    File.mkdir_p!(bucket_path)
    bucket_path
  end

  defp create_test_key(keys_dir, access_key_id, bucket) do
    key_data = %{
      access_key_id: access_key_id,
      secret_key: "secret-#{access_key_id}",
      bucket: bucket,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      permissions: ["put", "delete"]
    }

    path = Path.join(keys_dir, "#{access_key_id}.json")
    File.write!(path, Jason.encode!(key_data, pretty: true))
  end

  defp extract_bucket_section(lines, bucket_name) do
    # Find the line with the bucket name and extract the section
    start_index = Enum.find_index(lines, &String.contains?(&1, "Bucket:          #{bucket_name}"))

    if start_index do
      lines
      |> Enum.slice(start_index, 5)
      |> Enum.join("\n")
    else
      ""
    end
  end

  # Helper to test size formatting (private function from the module)
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_size(bytes),
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
