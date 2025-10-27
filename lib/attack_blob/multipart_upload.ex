defmodule AttackBlob.MultipartUpload do
  @moduledoc """
  Manages multipart upload sessions for large file uploads.

  Tracks active multipart uploads and their parts, providing AWS S3-compatible
  multipart upload functionality.
  """
  use GenServer
  require Logger

  @type upload_id :: String.t()
  @type part_number :: pos_integer()
  @type upload_info :: %{
          bucket: String.t(),
          key: String.t(),
          upload_id: upload_id(),
          parts: %{part_number() => %{etag: String.t(), size: non_neg_integer()}},
          initiated_at: DateTime.t()
        }

  ## Client API

  @doc """
  Starts the MultipartUpload GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initiates a new multipart upload.
<<<<<<< Updated upstream

  Returns a unique upload ID that must be used for subsequent part uploads.
=======
>>>>>>> Stashed changes
  """
  @spec initiate(String.t(), String.t()) :: {:ok, upload_id()}
  def initiate(bucket, key) do
    GenServer.call(__MODULE__, {:initiate, bucket, key})
  end

  @doc """
  Records an uploaded part.
<<<<<<< Updated upstream

  Parts must be numbered sequentially starting from 1.
=======
>>>>>>> Stashed changes
  """
  @spec add_part(upload_id(), part_number(), String.t(), non_neg_integer()) ::
          :ok | {:error, :upload_not_found}
  def add_part(upload_id, part_number, etag, size) do
    GenServer.call(__MODULE__, {:add_part, upload_id, part_number, etag, size})
  end

  @doc """
  Retrieves information about a multipart upload.
  """
  @spec get_upload(upload_id()) :: {:ok, upload_info()} | {:error, :not_found}
  def get_upload(upload_id) do
    GenServer.call(__MODULE__, {:get_upload, upload_id})
  end

  @doc """
  Lists all parts for a multipart upload.
  """
  @spec list_parts(upload_id()) :: {:ok, list()} | {:error, :not_found}
  def list_parts(upload_id) do
    GenServer.call(__MODULE__, {:list_parts, upload_id})
  end

  @doc """
  Completes a multipart upload, returning the part list.
  """
  @spec complete(upload_id()) :: {:ok, upload_info()} | {:error, :not_found}
  def complete(upload_id) do
    GenServer.call(__MODULE__, {:complete, upload_id})
  end

  @doc """
  Aborts a multipart upload, removing it from tracking.
  """
  @spec abort(upload_id()) :: :ok | {:error, :not_found}
  def abort(upload_id) do
    GenServer.call(__MODULE__, {:abort, upload_id})
  end

  @doc """
  Lists all active multipart uploads for a bucket.
  """
  @spec list_uploads(String.t()) :: list(upload_info())
  def list_uploads(bucket) do
    GenServer.call(__MODULE__, {:list_uploads, bucket})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
<<<<<<< Updated upstream
    # Use ETS for fast lookups
    table = :ets.new(:multipart_uploads, [:set, :protected, read_concurrency: true])

    # Schedule periodic cleanup of old uploads (older than 24 hours)
    schedule_cleanup()

=======
    table = :ets.new(:multipart_uploads, [:set, :protected, read_concurrency: true])
    schedule_cleanup()
>>>>>>> Stashed changes
    Logger.info("MultipartUpload manager started")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:initiate, bucket, key}, _from, state) do
    upload_id = generate_upload_id()

    upload_info = %{
      bucket: bucket,
      key: key,
      upload_id: upload_id,
      parts: %{},
      initiated_at: DateTime.utc_now()
    }

    :ets.insert(state.table, {upload_id, upload_info})
<<<<<<< Updated upstream

=======
>>>>>>> Stashed changes
    Logger.debug("Initiated multipart upload: #{upload_id} for #{bucket}/#{key}")
    {:reply, {:ok, upload_id}, state}
  end

  @impl true
  def handle_call({:add_part, upload_id, part_number, etag, size}, _from, state) do
    case :ets.lookup(state.table, upload_id) do
      [{^upload_id, upload_info}] ->
        part_info = %{etag: etag, size: size}
        updated_info = put_in(upload_info, [:parts, part_number], part_info)
        :ets.insert(state.table, {upload_id, updated_info})
<<<<<<< Updated upstream

        Logger.debug("Added part #{part_number} to upload #{upload_id}")
=======
>>>>>>> Stashed changes
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :upload_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_upload, upload_id}, _from, state) do
    case :ets.lookup(state.table, upload_id) do
      [{^upload_id, upload_info}] -> {:reply, {:ok, upload_info}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_parts, upload_id}, _from, state) do
    case :ets.lookup(state.table, upload_id) do
      [{^upload_id, upload_info}] ->
        parts =
          upload_info.parts
          |> Enum.map(fn {part_number, part_info} ->
<<<<<<< Updated upstream
            %{
              part_number: part_number,
              etag: part_info.etag,
              size: part_info.size
            }
=======
            %{part_number: part_number, etag: part_info.etag, size: part_info.size}
>>>>>>> Stashed changes
          end)
          |> Enum.sort_by(& &1.part_number)

        {:reply, {:ok, parts}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:complete, upload_id}, _from, state) do
    case :ets.lookup(state.table, upload_id) do
      [{^upload_id, upload_info}] ->
        :ets.delete(state.table, upload_id)
        Logger.info("Completed multipart upload: #{upload_id}")
        {:reply, {:ok, upload_info}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:abort, upload_id}, _from, state) do
    case :ets.lookup(state.table, upload_id) do
      [{^upload_id, _upload_info}] ->
        :ets.delete(state.table, upload_id)
        Logger.info("Aborted multipart upload: #{upload_id}")
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_uploads, bucket}, _from, state) do
    uploads =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {_upload_id, info} -> info.bucket == bucket end)
      |> Enum.map(fn {_upload_id, info} -> info end)

    {:reply, uploads, state}
  end

  @impl true
  def handle_info(:cleanup_old_uploads, state) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24, :hour)

    deleted_count =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {_upload_id, info} ->
        DateTime.compare(info.initiated_at, cutoff_time) == :lt
      end)
      |> Enum.map(fn {upload_id, _info} ->
        :ets.delete(state.table, upload_id)
        upload_id
      end)
      |> length()

    if deleted_count > 0 do
      Logger.info("Cleaned up #{deleted_count} old multipart uploads")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp generate_upload_id do
<<<<<<< Updated upstream
    # Generate a unique upload ID similar to AWS format
=======
>>>>>>> Stashed changes
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
    "#{timestamp}-#{random}"
  end

  defp schedule_cleanup do
<<<<<<< Updated upstream
    # Clean up old uploads every hour
=======
>>>>>>> Stashed changes
    Process.send_after(self(), :cleanup_old_uploads, :timer.hours(1))
  end
end
