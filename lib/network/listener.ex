defmodule Network.Listener do
  @moduledoc """
  Simple listener that accepts QUIC connections and delegates to ConnectionManager.
  """

  use GenServer
  import Network.Config
  alias Jamixir.Telemetry
  alias Network.ConnectionManager
  alias Network.CertUtils
  alias Util.Logger, as: Log
  import Util.Hex, only: [b16: 1]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Log.info("🔧 Starting QUIC listener...")
    port = Keyword.get(opts, :port, 9999)
    test_server_alias = Keyword.get(opts, :test_server_alias)
    pkcs12_bundle = Keyword.get(opts, :tls_identity, Application.get_env(:jamixir, :tls_identity))

    case :quicer.listen(port, quicer_listen_opts(pkcs12_bundle)) do
      {:ok, socket} ->
        Log.info("🎧 Listening on port #{port}")
        send(self(), :accept_connection)
        {:ok, %{socket: socket, test_server_alias: test_server_alias}}

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
        event_id = Telemetry.connecting_in(conn)

        case :quicer.handshake(conn) do
          {:ok, conn} ->
            Log.debug("🤝 Handshake completed successfully")

            case get_validator_ed25519_key(conn) do
              {:ok, ed25519_key} ->
                Log.info("✅ Identified validator, delegating to ConnectionManager")

                :ok =
                  :quicer.controlling_process(conn, Process.whereis(Network.ConnectionManager))

                # Pass test_server_alias if present in state
                opts =
                  if Map.get(state, :test_server_alias),
                    do: [test_server_alias: Map.get(state, :test_server_alias)],
                    else: []

                opts = opts ++ [event_id: event_id]
                ConnectionManager.handle_inbound_connection(conn, ed25519_key, opts)

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
  # Extract the validator's ed25519 key from the connection certificate
  defp get_validator_ed25519_key(conn) do
    case :quicer.peercert(conn) do
      {:ok, cert_der} ->
        case CertUtils.validate_certificate(cert_der) do
          {:ok, ed25519_key, alt_name} ->
            Log.debug("✅ Extracted ed25519 key from certificate: #{b16(ed25519_key)}")
            Log.debug("✅ Certificate alternative name: #{alt_name}")
            {:ok, ed25519_key}

          {:error, reason} ->
            Log.warning("❌ Failed to validate certificate: #{inspect(reason)}")
            :quicer.close_connection(conn)
            {:error, reason}
        end

      {:error, reason} ->
        Log.warning("❌ Failed to get peer certificate: #{inspect(reason)}")
        :quicer.close_connection(conn)
        {:error, reason}
    end
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @impl true
  def terminate(_reason, %{socket: socket}) do
    :ok = :quicer.close_listener(socket)
    :ok
  end
end
