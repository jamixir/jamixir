defmodule Network.Listener do
  @moduledoc """
  Simple listener that accepts QUIC connections and delegates to ConnectionManager.
  """

  use GenServer
  import Network.Config
  alias Network.ConnectionManager
  alias Util.Logger, as: Log
  import Utils, only: [format_ip_address: 1]

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
        case :quicer.handshake(conn) do
          {:ok, conn} ->
            case get_connection_info(conn) do
              {:ok, {remote_address, remote_port}} ->
                ConnectionManager.handle_inbound_connection(
                  conn,
                  remote_address,
                  remote_port,
                  Application.get_env(:jamixir, :port, 9999)
                )

              {:error, _reason} ->
                :quicer.close_connection(conn)
            end

          {:error, _reason} ->
            :quicer.close_connection(conn)
        end

      {:error, _reason} ->
        Process.send_after(self(), :accept_connection, 1000)
    end

    # Always continue accepting
    send(self(), :accept_connection)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private functions
  defp get_connection_info(conn) do
    case :quicer.peername(conn) do
      {:ok, {remote_ip, remote_port}} ->
        remote_address = format_ip_address(remote_ip)
        {:ok, {remote_address, remote_port}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
