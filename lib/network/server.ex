defmodule Network.Server do
  require Logger
  alias Quicer.Flags
  import Network.{MessageHandler, Codec}

  @log_context "[QUIC_SERVER]"

  def log(level, message), do: Logger.log(level, "#{@log_context} #{message}")

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

  def handle_data(data, stream, props, state) do
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
end
