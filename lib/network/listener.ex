defmodule Network.Listener do
  @moduledoc """
  Simple listener that accepts QUIC connections and delegates to ConnectionManager.
  """

  use GenServer
  import Network.Config
  alias Util.Hash
  alias Network.ConnectionManager
  alias System.State.Validator
  alias Jamixir.NodeCLIServer
  alias Util.Logger, as: Log

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 9999)

    case :quicer.listen(port, default_quicer_opts()) do
      {:ok, socket} ->
        Log.info("🎧 Listening on port #{port}")
        send(self(), :accept_connection)
        {:ok, %{socket: socket}}

      {:error, reason} ->
        Log.error("❌ Failed to start listener on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept_connection, %{socket: socket} = state) do
    case :quicer.accept(socket, [], :infinity) do
      {:ok, conn} ->
        Log.debug("📞 Accepted new QUIC connection")

        case :quicer.handshake(conn) do
          {:ok, conn} ->
            Log.debug("🤝 Handshake completed successfully")

            case get_validator_ed25519_key(conn) do
              {:ok, ed25519_key} ->
                Log.info("✅ Identified validator, delegating to ConnectionManager")
                ConnectionManager.handle_inbound_connection(conn, ed25519_key)

              {:error, reason} ->
                Log.warning("❌ Failed to identify validator: #{inspect(reason)}")
                :quicer.close_connection(conn)
            end

          {:error, reason} ->
            Log.warning("❌ Handshake failed: #{inspect(reason)}")
            :quicer.close_connection(conn)
        end

      {:error, reason} ->
        Log.debug("⏰ Accept failed, retrying: #{inspect(reason)}")
        Process.send_after(self(), :accept_connection, 1000)
    end

    # Always continue accepting
    send(self(), :accept_connection)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private functions
  # Temporary function to get the validator's ed25519 key from ip address (by matching to the metadata in the state)
  # this is a temporary solution , not good for production and can't be used for local testing (since all validators have the same ip)
  # we will replace this with a proper certificate-based identification in a future PR
  # TODO: extract the ed25519 key from the connection certificate
  defp get_validator_ed25519_key(conn) do
    case :quicer.peername(conn) do
      {:ok, {remote_ip, remote_port}} ->
        Log.debug("🔍 Connection from #{inspect(remote_ip)}: #{remote_port}")

        # Check if it's a localhost connection using tuple directly
        if is_localhost?(remote_ip) do
          Log.debug("🏠 Accepting localhost connection")
          # Generate a unique identifier for local connections
          unique_key = Hash.random()
          {:ok, unique_key}
        else
          # For non-local addresses: strict IP-based identification
          remote_address = format_ip_tuple(remote_ip)
          Log.debug("🔍 Connection from #{remote_address}:#{remote_port}")
          identify_validator_by_ip(remote_address)
        end

      {:error, reason} ->
        Log.warning("❌ Failed to get peer address: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Check if IP tuple represents localhost
  # IPv4 localhost
  defp is_localhost?({127, 0, 0, 1}), do: true
  # IPv6 localhost
  defp is_localhost?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp is_localhost?(_), do: false

  # Format IP tuple to string only when needed for validator identification (will not be used after we have a proper certificate-based identification)
  defp format_ip_tuple({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_ip_tuple({a, b, c, d, e, f, g, h}) do
    # Format IPv6 as standard hex format
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 4, "0"))
    |> Enum.join(":")
  end

  defp identify_validator_by_ip(remote_address) do
    case NodeCLIServer.inspect_state("curr_validators") do
      {:ok, validators} ->
        Log.debug("📋 Found #{length(validators)} validators, searching for IP #{remote_address}")

        case Validator.find_by_ip(validators, remote_address) do
          nil ->
            Log.warning("🚫 No validator found for IP #{remote_address}")
            {:error, :validator_not_found}

          validator ->
            Log.debug("✅ Found validator #{inspect(validator.ed25519)} for IP #{remote_address}")
            {:ok, validator.ed25519}
        end

      {:error, reason} ->
        Log.warning("❌ Failed to get validators from state: #{inspect(reason)}")
        {:error, :state_not_available}
    end
  end
end
