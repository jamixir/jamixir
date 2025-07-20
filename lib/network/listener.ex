defmodule Network.Listener do
  @moduledoc """
  Simple listener that accepts QUIC connections and delegates to ConnectionManager.
  """

  use GenServer
  import Network.Config
  alias Util.Hash
  alias Network.ConnectionManager
  alias System.State.Validator
  alias Jamixir.NodeStateServer
  alias Util.Logger, as: Log

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Log.info("🔧 Starting QUIC listener...")
    port = Keyword.get(opts, :port, 9999)
    test_server_alias = Keyword.get(opts, :test_server_alias)

    case :quicer.listen(port, default_quicer_opts()) do
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
        case extract_ed25519_key_from_certificate(cert_der) do
          {:ok, ed25519_key} ->
            Log.debug("✅ Extracted ed25519 key from certificate: #{inspect(ed25519_key)}")
            {:ok, ed25519_key}

          {:error, reason} ->
            Log.warning("❌ Failed to extract ed25519 key from certificate: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Log.warning("❌ Failed to get peer certificate: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Extract ed25519 public key from DER-encoded certificate
  defp extract_ed25519_key_from_certificate(cert_der) do
    case :public_key.pkix_decode_cert(cert_der, :otp) do
      {:ok, cert} ->
        case extract_ed25519_key_from_cert(cert) do
          {:ok, key} -> {:ok, key}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, {:cert_decode_failed, reason}}
    end
  end

  # Extract ed25519 key from decoded certificate
  defp extract_ed25519_key_from_cert(cert) do
    case cert.tbsCertificate.subjectPublicKeyInfo do
      %{algorithm: {:id_Ed25519, _}, subjectPublicKey: key_data} ->
        # Ed25519 public key is 32 bytes
        case key_data do
          <<key::binary-size(32)>> -> {:ok, key}
          _ -> {:error, :invalid_ed25519_key_size}
        end

      _ ->
        {:error, :not_ed25519_certificate}
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
