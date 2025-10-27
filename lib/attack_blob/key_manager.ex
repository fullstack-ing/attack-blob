defmodule AttackBlob.KeyManager do
  @moduledoc """
  GenServer that manages access keys in memory.

  Loads access keys from disk at startup and provides fast lookup
  functionality for authenticating requests.
  """

  use GenServer
  require Logger

  @type access_key :: %{
          access_key_id: String.t(),
          secret_key: String.t(),
          bucket: String.t(),
          created_at: String.t(),
          permissions: [String.t()]
        }

  ## Client API

  @doc """
  Starts the KeyManager GenServer.

  ## Options

    * `:data_dir` - Directory containing the keys folder (default: from app config)
    * `:name` - Name to register the GenServer (default: __MODULE__)

  """
  def start_link(opts \\ []) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    gen_opts = Keyword.put_new(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Looks up an access key by its access_key_id.

  Returns `{:ok, key}` if found, or `:error` if not found.

  ## Examples

      iex> KeyManager.lookup("AKIAIOSFODNN7EXAMPLE")
      {:ok, %{access_key_id: "AKIAIOSFODNN7EXAMPLE", ...}}

      iex> KeyManager.lookup("INVALID")
      :error

  """
  @spec lookup(String.t(), GenServer.server()) :: {:ok, access_key()} | :error
  def lookup(access_key_id, server \\ __MODULE__) do
    GenServer.call(server, {:lookup, access_key_id})
  end

  @doc """
  Returns all access keys.

  Returns a list of all loaded access keys.

  ## Examples

      iex> KeyManager.list_keys()
      [%{access_key_id: "AKIA...", ...}]

  """
  @spec list_keys(GenServer.server()) :: [access_key()]
  def list_keys(server \\ __MODULE__) do
    GenServer.call(server, :list_keys)
  end

  @doc """
  Reloads all keys from disk.

  Useful when keys have been added or removed from the filesystem.
  """
  @spec reload(GenServer.server()) :: :ok | {:error, term()}
  def reload(server \\ __MODULE__) do
    GenServer.call(server, :reload)
  end

  @doc """
  Returns the number of loaded keys.
  """
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server \\ __MODULE__) do
    GenServer.call(server, :count)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    data_dir =
      Keyword.get(opts, :data_dir) || Application.get_env(:attack_blob, :data_dir, "./data")

    keys_dir = Path.join(data_dir, "keys")

    # Create ETS table for fast lookups
    table = :ets.new(:access_keys, [:set, :protected, read_concurrency: true])

    state = %{
      keys_dir: keys_dir,
      table: table
    }

    # Load keys from disk
    case load_keys(state) do
      {:ok, count} ->
        Logger.info("KeyManager started: loaded #{count} access keys")
        {:ok, state}

      {:error, reason} ->
        Logger.error("KeyManager failed to load keys: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:lookup, access_key_id}, _from, state) do
    result =
      case :ets.lookup(state.table, access_key_id) do
        [{^access_key_id, key}] -> {:ok, key}
        [] -> :error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_keys, _from, state) do
    keys =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_id, key} -> key end)

    {:reply, keys, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    # Clear existing keys
    :ets.delete_all_objects(state.table)

    # Reload from disk
    case load_keys(state) do
      {:ok, count} ->
        Logger.info("KeyManager reloaded: #{count} access keys")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning("KeyManager reload failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:count, _from, state) do
    count = :ets.info(state.table, :size)
    {:reply, count, state}
  end

  ## Private Functions

  defp load_keys(state) do
    keys_dir = state.keys_dir

    # Ensure keys directory exists
    unless File.dir?(keys_dir) do
      File.mkdir_p!(keys_dir)
    end

    # Read all .json files from keys directory
    case File.ls(keys_dir) do
      {:ok, files} ->
        keys =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(&Path.join(keys_dir, &1))
          |> Enum.map(&read_key_file/1)
          |> Enum.reject(&is_nil/1)

        # Insert keys into ETS
        Enum.each(keys, fn key ->
          :ets.insert(state.table, {key.access_key_id, key})
        end)

        {:ok, length(keys)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_key_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, key_data} ->
            # Convert to our internal key structure
            %{
              access_key_id: key_data.access_key_id,
              secret_key: key_data.secret_key,
              bucket: key_data.bucket,
              created_at: key_data.created_at,
              permissions: key_data.permissions
            }

          {:error, reason} ->
            Logger.warning("Failed to parse key file #{path}: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        Logger.warning("Failed to read key file #{path}: #{inspect(reason)}")
        nil
    end
  end
end
