defmodule Jamixir.RPC.SubscriptionManager do
  @moduledoc """
  Manages RPC subscriptions for WebSocket connections.
  """

  use GenServer
  alias Util.Logger, as: Log
  import Codec.Encoder

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_subscription(method, params, websocket_pid) do
    GenServer.call(__MODULE__, {:create_subscription, method, params, websocket_pid})
  end

  def unsubscribe(subscription_id) do
    GenServer.cast(__MODULE__, {:unsubscribe, subscription_id})
  end

  def notify_subscribers(method, data) do
    GenServer.cast(__MODULE__, {:notify, method, data})
  end

  @impl true
  def init(_opts) do
    Log.info("📡 Starting RPC Subscription Manager")
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

    Log.debug("📡 Created subscription #{subscription_id} for method #{method}")

    new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription)
    new_state = %{state | subscriptions: new_subscriptions, next_id: state.next_id + 1}

    {:reply, subscription_id, new_state}
  end

  @impl true
  def handle_cast({:unsubscribe, subscription_id}, state) do
    Log.debug("📡 Unsubscribed #{subscription_id}")
    new_subscriptions = Map.delete(state.subscriptions, subscription_id)
    {:noreply, %{state | subscriptions: new_subscriptions}}
  end

  @impl true
  def handle_cast({:notify, method, data}, state) do
    # Notify all subscriptions matching the method
    for {_id, subscription} <- state.subscriptions do
      if subscription.method == method do
        send(subscription.websocket_pid, {:subscription_data, subscription.id, data})
      end
    end

    {:noreply, state}
  end

  # Handle PubSub messages and convert them to subscription notifications
  @impl true
  def handle_info({:new_block, header}, state) do
    Log.info("RPC Notify new block")
    # When we get new_block event, we can notify bestBlock subscribers
    Task.start(fn ->
      hash = h(e(header))

      notify_subscribers("bestBlock", [hash |> :binary.bin_to_list(), header.timeslot])
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
