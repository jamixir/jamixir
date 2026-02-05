defmodule Jamixir.RPC.WebSocketHandler do
  @moduledoc """
  WebSocket handler for JSON-RPC requests and subscriptions.
  """

  alias Jamixir.RPC.{Handler, SubscriptionManager}
  require Logger

  @behaviour WebSock

  def init(_) do
    {:ok, %{subscriptions: %{}}}
  end

  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, json_rpc_request} ->
        response = Handler.handle_request(json_rpc_request, self())

        case response do
          # Handle subscription responses
          {:subscription, subscription_id} ->
            new_subscriptions = Map.put(state.subscriptions, subscription_id, json_rpc_request)
            {:reply, :ok, nil, %{state | subscriptions: new_subscriptions}}

          # Handle regular responses
          _ ->
            {:reply, :ok, {:text, Jason.encode!(response)}, state}
        end

      {:error, _} ->
        error_response = %{
          jsonrpc: "2.0",
          error: %{code: -32700, message: "Parse error"},
          id: nil
        }

        {:reply, :ok, {:text, Jason.encode!(error_response)}, state}
    end
  end

  def handle_info({:subscription_data, subscription_id, method, data}, state) do
    # Send subscription notification using original method name like polkajam
    notification = %{
      jsonrpc: "2.0",
      method: method,
      params: %{
        subscription: subscription_id,
        result: data
      }
    }

    {:reply, :ok, {:text, Jason.encode!(notification)}, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    # Clean up subscriptions
    for {subscription_id, _} <- state.subscriptions do
      SubscriptionManager.unsubscribe(subscription_id)
    end

    :ok
  end
end
