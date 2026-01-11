defmodule Jamixir.NodeIdentity do
  alias Util.Hex

  # Key for persistent_term storage
  @node_id_key {__MODULE__, :node_id}
  @initialized_key {__MODULE__, :initialized}

  @spec initialize!() :: String.t()
  def initialize! do
    if :persistent_term.get(@initialized_key, false) do
      # Already initialized, return stored value
      :persistent_term.get(@node_id_key)
    else
      node_id =
        if Application.get_env(:jamixir, :fuzzer_mode, false) do
          compute_fuzzer_node_id()
        else
          compute_validator_node_id()
        end

      :persistent_term.put(@node_id_key, node_id)
      :persistent_term.put(@initialized_key, true)
      node_id
    end
  end

  @doc """
  Returns a node identifier for fuzzer mode.
  Uses Blake2.Blake2b directly to avoid Memoize dependency since
  this may be called before the application fully starts.
  """
  @spec node_id() :: String.t()
  def node_id do
    case :persistent_term.get(@initialized_key, false) do
      true ->
        :persistent_term.get(@node_id_key)

      false ->
        raise """
        NodeIdentity not initialized.
        Call Jamixir.NodeIdentity.initialize!() before accessing node_id/0.
        """
    end
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

  defp compute_fuzzer_node_id do
    pid = System.pid()
    ts = System.monotonic_time()
    # Salt with monotonic time
    # Use direct Blake2b call instead of Hash.default() to avoid memoization
    hash = Blake2.Blake2b.hash("#{pid}:#{ts}", <<>>, 32)
    hex = Hex.b16n(hash) |> String.slice(0, 16)
    "fuzzer_" <> hex
  end

  defp compute_validator_node_id do
    # Keys must be loaded before storage initialization
    case KeyManager.get_our_ed25519_key() do
      nil ->
        raise """
        Cannot determine node_id: ed25519 key not loaded.
        """

      public_key ->
        Network.CertUtils.alt_name(public_key)
    end
  end
end
