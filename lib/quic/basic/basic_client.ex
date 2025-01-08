defmodule BasicQuicClient do
  use GenServer
  import Quic.Basic.Flags
  @call_default_config [host: ~c"localhost", port: 9999, timeout: 5_000]

  defmodule State do
    @initial_stream_id 128
    defstruct [
      :conn,
      next_stream_id: @initial_stream_id,
      # Map of stream -> {from, timer_ref}
      streams: %{}
    ]
  end

  def start_link(config \\ []) do
    conf = Keyword.merge(@call_default_config, config)
    GenServer.start_link(__MODULE__, conf, name: __MODULE__)
  end

  def send_and_wait(pid, message) do
    GenServer.call(pid, {:send_and_wait, message}, 5_000)
  end

  def init(conf) do
    IO.puts("Client connecting...")

    case :quicer.connect(
           conf[:host],
           conf[:port],
           QuicServer.default_opts(),
           conf[:timeout]
         ) do
      {:ok, conn} ->
        IO.puts("Client connected")
        {:ok, %State{conn: conn}}

      error ->
        IO.puts("Client connection failed: #{inspect(error)}")
        {:stop, error}
    end
  end

  def handle_call({:send_and_wait, message}, from, %State{} = state) do
    stream_id = state.next_stream_id
    IO.puts("Starting stream with ID: #{stream_id}")

    stream_opts = %{
      active: true,
      stream_id: stream_id,
      start_flag: stream_start_flag(:indicate_peer_accept),
      open_flag: stream_open_flag(:none)
    }

    {:ok, stream} =
      :quicer.start_stream(state.conn, stream_opts)

    IO.puts("Stream started: #{inspect(stream)}")

    length = byte_size(message)

    payload = <<stream_id::8, length::32-little, message::binary>>

    # case :quicer.send(stream, <<random_number>>) do
    #   {:ok, _} -> IO.puts("Sent random number")
    #   err -> IO.puts("Error sending random number: #{inspect(err)}")
    # end

    case :quicer.send(stream, payload) do
      {:ok, _} -> IO.puts("Sent payload")
      err -> IO.puts("Error sending payload: #{inspect(err)}")
    end

    timer_ref = Process.send_after(self(), {:stream_timeout, stream}, 5_000)
    IO.puts("Set up timeout for stream: #{inspect(stream)}")

    new_state = %State{
      state
      | next_stream_id: stream_id + 4,
        streams: Map.put(state.streams, stream, {from, timer_ref})
    }

    {:noreply, new_state}
  end

  # def handle_call({:send_and_wait, message}, from, %State{} = state) do
  #   stream_id = state.next_stream_id

  #   stream_opts = %{
  #     active: true,
  #     stream_id: stream_id,
  #     start_flag: stream_start_flag(:indicate_peer_accept),
  #     open_flag: stream_open_flag(:none)
  #   }

  #   case :quicer.start_stream(state.conn, stream_opts) do
  #     {:ok, stream} ->
  #       new_state = %{
  #         state
  #         | next_stream_id: stream_id + 1,
  #           streams:
  #             Map.put(state.streams, stream, %{from: from, message: message, stream_id: stream_id})
  #       }
  #       IO.puts("Client started stream #{stream_id}")

  #       {:noreply, new_state}

  #     error ->
  #       IO.puts("Client failed to start stream #{stream_id}: #{inspect(error)}")
  #       {:reply, error, state}
  #   end
  # end

  # def handle_info({:quic, :peer_accepted, stream, _}, %State{streams: streams} = state) do
  #   IO.puts("Client received peer accepted")
  #   case Map.get(streams, stream) do
  #     %{from: _from, message: message, stream_id: stream_id} ->

  #       length = byte_size(message)
  #       payload = <<stream_id::8, length::32-little, message::binary>>
  #       {:ok, _} = :quicer.send(stream, payload)
  #       IO.puts("Client sent payload")
  #       {:noreply, state}

  #     nil ->
  #       {:noreply, state}
  #   end
  # end

  # def handle_info({:quic, data, stream, _props}, %State{streams: streams} = state)
  #     when is_binary(data) do
  #   case Map.get(streams, stream) do
  #     %{from: from, message: _message} ->
  #       GenServer.reply(from, {:ok, data})
  #       {:noreply, %{state | streams: Map.delete(streams, stream)}}

  #     nil ->
  #       {:noreply, state}
  #   end
  # end

  def handle_info({:quic, data, stream, _props}, %State{} = state) when is_binary(data) do
    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      {from, timer_ref} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:ok, {:ok, data}})
        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
    end
  end

  def handle_info({:quic, :stream_closed, stream, _props}, %State{} = state) do
    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      {from, timer_ref} ->
        Process.cancel_timer(timer_ref)
        # GenServer.reply(from, :ok)
        if Process.alive?(from), do: GenServer.reply(from, :ok)

        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
    end
  end

  def handle_info({:stream_timeout, stream}, %State{} = state) do
    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      {from, _timer_ref} ->
        GenServer.reply(from, {:error, :timeout})
        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
    end
  end

  # Handle other QUIC events
  def handle_info({:quic, :peer_send_shutdown, stream, _undefined}, state) do
    # Just log for now
    IO.puts("Stream #{inspect(stream)} peer send shutdown")
    {:noreply, state}
  end

  def handle_info({:quic, :peer_send_aborted, stream, error_code}, %State{} = state) do
    case Map.get(state.streams, stream) do
      nil ->
        {:noreply, state}

      {from, timer_ref} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:error, {:aborted, error_code}})
        new_state = %State{state | streams: Map.delete(state.streams, stream)}
        {:noreply, new_state}
    end
  end

  # Catch-all for unhandled QUIC events
  def handle_info({:quic, event_name, _resource, _props} = msg, state) do
    IO.puts("BasicQuicClient received unhandled QUIC event: #{inspect(event_name)}")
    {:noreply, state}
  end

  # Super catch-all for any other messages
  def handle_info(msg, state) do
    IO.puts("BasicQuicClient received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
