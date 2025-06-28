defmodule Network.ConnectionPolicy do
  @moduledoc """
  Connection policies and business rules.
  used by ConnectionManager to make decisions about connection attempts, retries, and protocol decisions.
  """

  alias Network.ConnectionManager
  alias Util.Logger, as: Log
  alias System.State.Validator

  @type connection_attempt_result :: {connection_outcome(), Types.ed25519_key()}
  @type connection_outcome :: :skip_self | :connect_success | :connect_failure | :wait_inbound

  # Configuration constants
  # 2 seconds
  @initial_retry_delay 2000
  @retry_multiplier 2
  # 32 seconds
  @max_retry_delay 32000
  # 5 minutes
  @max_retry_duration 300_000

  ## Public API

  @spec attempt_connections(list(Validator.t())) :: list(connection_attempt_result())
  def attempt_connections(validators) do
    our_ed25519_key = KeyManager.get_our_ed25519_key()

    Enum.map(validators, fn %Validator{ed25519: ed25519_key} = v ->
      cond do
        our_ed25519_key == ed25519_key ->
          Log.connection(:debug, "⏭️ Skipping self-connection", ed25519_key)
          {:skip_self, ed25519_key}

        should_initiate_connection?(v, our_ed25519_key) ->
          Log.connection(:debug, "🔌 Attempting connection", ed25519_key)

          case attempt_connection(v) do
            {:ok, _result} ->
              Log.connection(:info, "✅ Connected", ed25519_key)
              {:connect_success, ed25519_key}

            {:error, reason} ->
              Log.connection(:debug, "❌ Connection failed: #{inspect(reason)}", ed25519_key)
              {:connect_failure, ed25519_key}
          end

        true ->
          Log.connection(:debug, "👂 Waiting for inbound connection", ed25519_key)
          {:wait_inbound, ed25519_key}
      end
    end)
  end

  def attempt_connection(%Validator{ed25519: ed25519_key} = v) do
    {ip, port} = Validator.ip_port(v)

    case ConnectionManager.start_outbound_connection(ed25519_key, ip, port) do
      {:ok, pid} ->
        Log.connection(:info, "✅ Connected", ed25519_key)
        {:ok, %{type: :new, pid: pid}}

      {:error, reason} ->
        Log.connection(:debug, "❌ Connection failed: #{inspect(reason)}", ed25519_key)
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

  def should_initiate_connection?(v, our_key \\ nil)

  def should_initiate_connection?(%Validator{ed25519: target_key}, our_key) do
    our_key = our_key || KeyManager.get_our_ed25519_key()
    should_initiate_connection?(target_key, our_key)
  end

  def should_initiate_connection?(target_key, our_key) do
    our_key = our_key || KeyManager.get_our_ed25519_key()
    our_key == Network.Rules.preferred_initiator(our_key, target_key)
  end
end
