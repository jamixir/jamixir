defmodule Network.Server do
  use GenServer
  alias Network.CertUtils
  require Logger
  alias Quicer.Flags
  import Network.MessageHandler

  @log_context "[QUIC_SERVER]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

  defmodule State do
    defstruct [
      :socket,
      :connection,
      streams: %{},
      up_streams: %{}
    ]
  end

  @fixed_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: 1023,
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_opts [
                  certfile: ~c"#{CertUtils.certfile()}",
                  keyfile: ~c"#{CertUtils.keyfile()}"
                ] ++ @fixed_opts

  def default_opts, do: @default_opts

  def start_link(port, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, port, name: name)
  end

  def init(port) do
    log(:info, "Starting on port #{port}")
    case :quicer.listen(port, @default_opts) do
      {:ok, socket} ->
        send(self(), :accept_connection)
        {:ok, %State{socket: socket}}

      {:error, :listener_start_error, _reason} = error ->
        {:stop, error}

      error ->
        {:stop, error}
    end
  end

  def handle_info(:accept_connection, %{socket: socket} = state) do
    case :quicer.accept(socket, [], :infinity) do
      {:ok, conn} ->
        log(:info, "Connection accepted")
        {:ok, conn} = :quicer.handshake(conn)
        log(:info, "Handshake completed")
        send(self(), :accept_stream)
        {:noreply, %{state | connection: conn}}

      error ->
        log(:error, "Accept error: #{inspect(error)}")
        send(self(), :accept_connection)
        {:noreply, state}
    end
  end

  def handle_info(:accept_stream, %{connection: conn} = state) do
    case :quicer.accept_stream(conn, [{:active, true}], 0) do
      {:ok, stream} ->
        log(:debug, "Stream accepted: #{inspect(stream)}")
        send(self(), :accept_stream)
        {:noreply, state}

      {:error, :timeout} ->
        # Normal case - no streams to accept right now
        send(self(), :accept_stream)
        {:noreply, state}

      {:error, reason} when reason in [:badarg, :internal_error, :bad_pid, :owner_dead] ->
        log(:error, "Stream accept error: #{inspect(reason)}")
        send(self(), :accept_stream)
        {:noreply, state}
    end
  end

  def handle_info({:quic, data, stream, props}, state) when is_binary(data) do
    handle_stream_data(data, stream, props, state,
      log_tag: "[QUIC_SERVER]",
      on_complete: fn protocol_id, message, stream ->
        if protocol_id >= 128 do
          response = Network.ServerCalls.call(protocol_id, message)

          {:ok, _} =
            :quicer.send(stream, encode_message(protocol_id, response), Flags.send_flag(:fin))
        else
          Task.start(fn -> Network.ServerCalls.call(protocol_id, message) end)
        end
      end
    )
  end

  def handle_info({:quic, :stream_closed, stream, _props}, state) do
    log(:info, "Stream closed: #{inspect(stream)}")
    {:noreply, %{state | streams: Map.delete(state.streams, stream)}}
  end

  def handle_info({:quic, event_name, _stream, _props} = _msg, state) do
    log(:debug, "Received unhandled event: #{inspect(event_name)}")

    {:noreply, state}
  end
end
