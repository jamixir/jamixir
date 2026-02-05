defmodule Jamixir.RPC.SubscriptionManager do
  @moduledoc """
  Manages RPC subscriptions for WebSocket connections.
  """

  use GenServer
  import Codec.Encoder
  import Util.Hex

  @buffer_timeout 5_000
  @log_context "[RPC][SUBSCRIPTIONS]"
  use Util.Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_subscription(method, params, websocket_pid) do
    GenServer.call(__MODULE__, {:create_subscription, method, params, websocket_pid})
  end

  def unsubscribe(subscription_id) do
    GenServer.cast(__MODULE__, {:unsubscribe, subscription_id})
  end

  def notify_subscribers(method, params, data) do
    GenServer.cast(__MODULE__, {:notify, method, params, data})
  end

  @impl true
  def init(_opts) do
    log("📡 Starting RPC Subscription Manager")
    Phoenix.PubSub.subscribe(Jamixir.PubSub, "node_events")

    {:ok, %{subscriptions: %{}, next_id: 1, buffer: []}}
  end

  @impl true
  def handle_call({:create_subscription, method, params, websocket_pid}, _from, state) do
    # Use numeric subscription IDs like polkajam does
    subscription_id = state.next_id

    subscription = %{
      id: subscription_id,
      method: method,
      params: params,
      websocket_pid: websocket_pid
    }

    debug("📡 Created subscription #{subscription_id} for method #{method}")

    new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription)

    new_buffer =
      for {buf_method, params, data, timing} <- state.buffer,
          # filter out old buffer entries
          timing >= System.monotonic_time(:millisecond) - @buffer_timeout do
        if subscription.method == buf_method and subscription.params == params do
          debug(
            "📡 Sending buffered data to new subscription #{subscription_id}, #{inspect(data)}"
          )

          notify_method =
            "subscribe" <>
              String.capitalize(String.at(buf_method, 0)) <> String.slice(buf_method, 1..-1//1)

          send(
            subscription.websocket_pid,
            {:subscription_data, subscription.id, notify_method, data}
          )
        end

        {buf_method, params, data, timing}
      end

    new_state = %{
      state
      | subscriptions: new_subscriptions,
        next_id: state.next_id + 1,
        buffer: new_buffer
    }

    {:reply, subscription_id, new_state}
  end

  @impl true
  def handle_cast({:unsubscribe, subscription_id}, state) do
    debug("📡 Unsubscribed #{subscription_id}")
    new_subscriptions = Map.delete(state.subscriptions, subscription_id)
    {:noreply, %{state | subscriptions: new_subscriptions}}
  end

  @impl true
  def handle_cast({:notify, method, params, data}, state) do
    # Notify all subscriptions matching the method
    # Include the method name in the message for proper notification formatting
    for {_id, subscription} <- state.subscriptions,
        subscription.method == method and subscription.params == params do
      debug("📡 Notifying subscription #{subscription.id} for method #{method}")

      # Send method name as "subscribe" + method for notification (e.g., "subscribeFinalizedBlock")
      notify_method =
        "subscribe" <> String.capitalize(String.at(method, 0)) <> String.slice(method, 1..-1//1)

      send(subscription.websocket_pid, {:subscription_data, subscription.id, notify_method, data})
    end

    new_buffer = [{method, params, data, System.monotonic_time(:millisecond)} | state.buffer]

    {:noreply, %{state | buffer: new_buffer}}
  end

  # Handle PubSub messages and convert them to subscription notifications
  @impl true
  def handle_info({:new_block, block}, state) do
    debug("RPC Notify new block")
    # Extract header from the block
    header = block.header

    # When we get new_block event, we can notify bestBlock subscribers
    # Use object format like polkajam: {"header_hash": ..., "slot": ...}
    Task.start(fn ->
      message = %{"header_hash" => e64(h(e(header))), "slot" => header.timeslot}
      notify_subscribers("bestBlock", [], message)
      notify_subscribers("finalizedBlock", [], message)
    end)

    {:noreply, state}
  end

  def handle_info({:service_request, [service_id, hash, size], csu}, state) do
    %{header_hash: header_hash, timeslot: slot, value: value} = csu
    message = %{"header_hash" => e64(header_hash), "slot" => slot, "value" => value}
    debug("Notifying serviceRequest #{service_id}, {#{b16(hash)},#{size}}: #{inspect(value)}")
    notify_subscribers("serviceRequest", [service_id, hash, size, false], message)
    {:noreply, state}
  end

  def handle_info({:service_value, [service_id, key], csu}, state) do
    %{header_hash: header_hash, timeslot: slot, value: value} = csu
    json_value = if is_nil(value), do: nil, else: e64(value)
    message = %{"header_hash" => e64(header_hash), "slot" => slot, "value" => json_value}
    debug("Notifying serviceValue #{service_id}, #{b16(key)}: #{inspect(value)}")
    notify_subscribers("serviceValue", [service_id, key], message)
    {:noreply, state}
  end

  def handle_info({:clock, :sync_status}, state) do
    debug("Notify sync status")

    Task.start(fn ->
      notify_subscribers("syncStatus", [], "Completed")
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
