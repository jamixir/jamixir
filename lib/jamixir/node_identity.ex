defmodule Jamixir.NodeIdentity do
  alias Util.Hash
  alias Util.Hex

  @spec node_id() :: String.t()
  def node_id do
    # Check if node_id was pre-computed and stored (locked)
    case Application.get_env(:jamixir, :node_id) do
      nil ->
        # Keys must be loaded before storage initialization
        case KeyManager.get_our_ed25519_key() do
          nil ->
            raise """
            Cannot determine node_id: ed25519 key not loaded.
            """

          public_key ->
            Network.CertUtils.alt_name(public_key)
        end

      stored_id ->
        stored_id
    end
  end

  @doc """
  Returns a node identifier for fuzzer mode
  """
  @spec node_id_fuzzer() :: String.t()
  def node_id_fuzzer do
    pid = System.pid()
    ts = System.monotonic_time()
    # Salt with monotonic time
    hex =
      "#{pid}:#{ts}"
      |> Hash.default()
      |> Hex.b16n()
      |> String.slice(0, 16)

    "fuzzer_" <> hex
  end

  @spec assert_node_id_locked!() :: :ok
  def assert_node_id_locked! do
    # Only enforce strict node_id requirements in prod/tiny runtime environments

    case Mix.env() do
      env when env in [:prod, :tiny] ->
        case Application.get_env(:jamixir, :node_id) do
          nil ->
            raise """
            node_id not initialized. This indicates a startup order problem.

            Storage isolation requires node_id to be set in Commands.Run
            before any storage access (Mnesia, CubDB, SQLite).

            Ensure keys are loaded and node_id is computed before Application.ensure_all_started(:jamixir).
            """

          _ ->
            :ok
        end

      _ ->
        # In test/dev environments, be more lenient
        :ok
    end
  end

  @spec base_dir() :: String.t()
  def base_dir do
    Application.get_env(:jamixir, :storage_root) ||
      Path.join(System.user_home!(), ".jamixir")
  end

  @spec node_dir() :: String.t()
  def node_dir do
    assert_node_id_locked!()
    Path.join(base_dir(), node_id())
  end
end
