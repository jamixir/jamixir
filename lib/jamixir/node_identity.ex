defmodule Jamixir.NodeIdentity do
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
  Returns a node identifier for fuzzer mode.
  Uses Blake2.Blake2b directly to avoid Memoize dependency since
  this may be called before the application fully starts.
  """
  @spec node_id_fuzzer() :: String.t()
  def node_id_fuzzer do
    pid = System.pid()
    ts = System.monotonic_time()
    # Salt with monotonic time - use Blake2 directly to avoid Memoize dependency
    hex =
      "#{pid}:#{ts}"
      |> Blake2.Blake2b.hash(<<>>, 32)
      |> Hex.b16n()
      |> String.slice(0, 16)

    "fuzzer_" <> hex
  end

  @spec base_dir() :: String.t()
  def base_dir do
    Application.get_env(:jamixir, :storage_root) ||
      Path.join(System.user_home!(), ".jamixir")
  end

  @spec node_dir() :: String.t()
  def node_dir do
    Path.join(base_dir(), node_id())
  end

  @spec initialize!() :: String.t()
  def initialize! do
    node_id =
      if Application.get_env(:jamixir, :fuzzer_mode, false) do
        node_id_fuzzer()
      else
        node_id()
      end

    Application.put_env(:jamixir, :node_id, node_id)
    node_id
  end
end
