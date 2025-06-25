defmodule Network.ConnectionPolicy do
  @moduledoc """
  Connection policies and business rules.
  used by ConnectionManager to make decisions about connection attempts, retries, and protocol decisions.
  """

  alias Network.ConnectionSupervisor
  alias Util.Logger, as: Log
  import System.State.Validator, only: [address: 1, ip_address: 1, port: 1]

  # Configuration constants
  @initial_retry_delay 2000  # 2 seconds
  @retry_multiplier 2
  @max_retry_delay 32000  # 32 seconds
  @max_retry_duration 300_000  # 5 minutes

  ## Public API

  def attempt_connections(targets) do
    Enum.map(targets, fn target ->
      address = get_address(target)

      our_address = Application.get_env(:jamixir, :our_validator_address)

      if our_address == address do
        Log.connection(:debug, "⏭️ Skipping self-connection", address)
        {:skip_self, address, target}
      else
        if should_initiate_connection?(target) do
          Log.connection(:debug, "🔌 Attempting connection", address)

          case attempt_connection(target) do
            {:ok, result} -> {:connect_success, address, result, target}
            {:error, reason} -> {:connect_failure, address, reason, target}
          end
        else
          Log.connection(:debug, "👂 Waiting for inbound connection", address)
          {:wait_inbound, address, target}
        end
      end
    end)
  end

  def attempt_connection(target) do
    address = get_address(target)
    {ip, port} = get_ip_port(target)

    case ConnectionSupervisor.start_outbound_connection(ip, port) do
      {:ok, pid} ->
        Log.connection(:info, "✅ Connected", address)
        {:ok, %{type: :new, pid: pid}}

      {:error, reason} ->
        Log.connection(:debug, "❌ Connection failed: #{inspect(reason)}", address)
        {:error, reason}
    end
  end

  def calculate_retry_delay(retry_count) do
    delay = @initial_retry_delay * :math.pow(@retry_multiplier, retry_count - 1)
    min(delay, @max_retry_delay) |> round()
  end

  def should_retry?(start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    elapsed < @max_retry_duration
  end


  def should_initiate_connection?(target) do
    our_key = KeyManager.get_our_ed25519_key()
    target_key = Map.get(target, :ed25519)

    preferred = Network.Rules.preferred_initiator(our_key, target_key)
    preferred == our_key
  end

  ## Helper Functions

  defp get_address(%{address: address}), do: address
  defp get_address(validator), do: address(validator)

  defp get_ip_port(%{ip_address: ip, port: port}), do: {ip, port}
  defp get_ip_port(validator), do: {ip_address(validator), port(validator)}
end
