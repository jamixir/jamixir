defmodule Jamixir.RPC.SubscriptionManager do
  @moduledoc """
  Manages RPC subscriptions for WebSocket connections.
  """

  use GenServer
  import Codec.Encoder
  import Util.Hex

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

    {:ok, %{subscriptions: %{}, next_id: 1}}
  end

  @impl true
  def handle_call({:create_subscription, method, params, websocket_pid}, _from, state) do
    subscription_id = "0x#{Integer.to_string(state.next_id, 16)}"

    subscription = %{
      id: subscription_id,
      method: method,
      params: params,
      websocket_pid: websocket_pid
    }

    debug("📡 Created subscription #{subscription_id} for method #{method}")

    new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription)
    new_state = %{state | subscriptions: new_subscriptions, next_id: state.next_id + 1}

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
    for {_id, subscription} <- state.subscriptions do
      if subscription.method == method and subscription.params == params do
        send(subscription.websocket_pid, {:subscription_data, subscription.id, data})
      end
    end

    {:noreply, state}
  end

  # Handle PubSub messages and convert them to subscription notifications
  @impl true
  def handle_info({:new_block, block}, state) do
    debug("RPC Notify new block")
    # Extract header from the block
    header = block.header

    # When we get new_block event, we can notify bestBlock subscribers
    Task.start(fn ->
      message = [e64(h(e(header))), header.timeslot]
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
    message = %{"header_hash" => e64(header_hash), "slot" => slot, "value" => e64(value)}
    debug("Notifying serviceValue #{service_id}, #{b16(key)}: #{b16(value)}")
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
