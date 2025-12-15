defmodule Jamixir.Telemetry.Client do
  @moduledoc """
  Telemetry client implementing JIP-3 specification.
  Handles connection to telemetry server and message sending.
  """

  use GenServer
  require Logger
  alias Jamixir.Telemetry.NodeInfo
  import Network.Codec
  import Codec.Encoder

  @reconnect_delay 60_000
  @buffer_max_size 1000

  defstruct [
    :host,
    :port,
    :socket,
    :event_id,
    :buffer,
    :enabled
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a telemetry event. Returns :ok immediately without blocking.
  """
  def send_event(event) do
    GenServer.cast(__MODULE__, {:send_event, event})
  end

  @doc """
  Get the next event ID and increment the counter
  """
  def get_event_id do
    GenServer.call(__MODULE__, :get_event_id)
  end

  @impl true
  def init(opts) do
    enabled = opts[:enabled] || false

    state = %__MODULE__{
      host: opts[:host],
      port: opts[:port],
      socket: nil,
      event_id: 0,
      buffer: :queue.new(),
      enabled: enabled
    }

    if enabled do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_event_id, _from, state) do
    {:reply, state.event_id, %{state | event_id: state.event_id + 1}}
  end

  @impl true
  def handle_cast({:send_event, _event}, %{enabled: false} = state) do
    # Telemetry disabled, ignore
    {:noreply, state}
  end

  def handle_cast({:send_event, event}, %{socket: nil} = state) do
    # Not connected, buffer the event
    new_buffer = buffer_event(state.buffer, event)
    {:noreply, %{state | buffer: new_buffer}}
  end

  def handle_cast({:send_event, event}, state) do
    case do_send_event(state.socket, event) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Failed to send telemetry event: #{inspect(reason)}")
        # Close socket and reconnect
        :gen_tcp.close(state.socket)
        send(self(), :connect)
        # Buffer the event
        new_buffer = buffer_event(state.buffer, event)
        {:noreply, %{state | socket: nil, buffer: new_buffer}}
    end
  end

  @impl true
  def handle_info(:connect, %{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    case :gen_tcp.connect(
           String.to_charlist(state.host),
           state.port,
           [:binary, active: false, packet: :raw],
           5000
         ) do
      {:ok, socket} ->
        Logger.info("Connected to telemetry server at #{state.host}:#{state.port}")

        # Send node information message
        case send_node_info(socket) do
          :ok ->
            # Send any buffered events
            new_buffer = flush_buffer(socket, state.buffer)
            {:noreply, %{state | socket: socket, buffer: new_buffer}}

          {:error, reason} ->
            Logger.error("Failed to send node info: #{inspect(reason)}")
            :gen_tcp.close(socket)
            schedule_reconnect()
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to connect to telemetry server: #{inspect(reason)}")
        schedule_reconnect()
        {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.warning("Telemetry connection closed")
    schedule_reconnect()
    {:noreply, %{state | socket: nil}}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warning("Telemetry connection error: #{inspect(reason)}")
    if state.socket, do: :gen_tcp.close(state.socket)
    schedule_reconnect()
    {:noreply, %{state | socket: nil}}
  end

  defp send_node_info(socket) do
    encoded = encode_message(e(NodeInfo.build()))
    :gen_tcp.send(socket, encoded)
  end

  defp do_send_event(socket, event) do
    :gen_tcp.send(socket, encode_message(e(event)))
  end

  defp buffer_event(buffer, event) do
    if :queue.len(buffer) >= @buffer_max_size do
      # Drop oldest event
      {{:value, _}, new_queue} = :queue.out(buffer)
      :queue.in(event, new_queue)
    else
      :queue.in(event, buffer)
    end
  end

  defp flush_buffer(socket, buffer) do
    case :queue.out(buffer) do
      {{:value, event}, new_buffer} ->
        case do_send_event(socket, event) do
          :ok -> flush_buffer(socket, new_buffer)
          {:error, _} -> buffer
        end

      {:empty, buffer} ->
        buffer
    end
  end

  defp schedule_reconnect do
    Process.send_after(self(), :connect, @reconnect_delay)
  end
end
