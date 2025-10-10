defmodule Jamixir.RPC.Handler do
  @moduledoc """
  Main RPC handler that processes JSON-RPC method calls according to JIP-2 specification.
  """

  alias Jamixir.RPC.SubscriptionManager
  alias Util.Logger, as: Log
  import Codec.Encoder

  @spec handle_request(map(), pid() | nil) :: map() | {:subscription, binary()}
  def handle_request(request, websocket_pid \\ nil)

  # Handle batch requests
  def handle_request(requests, websocket_pid) when is_list(requests) do
    Enum.map(requests, &handle_request(&1, websocket_pid))
  end

  # Handle single request
  def handle_request(%{"jsonrpc" => "2.0"} = request, websocket_pid) do
    method = Map.get(request, "method")
    params = Map.get(request, "params", [])
    id = Map.get(request, "id")

    Log.debug("🔧 Processing RPC method: #{method}")

    case handle_method(method, params, websocket_pid) do
      {:ok, result} ->
        %{
          jsonrpc: "2.0",
          result: result,
          id: id
        }

      {:subscription, subscription_id} ->
        %{
          jsonrpc: "2.0",
          result: subscription_id,
          id: id
        }

      {:error, code, message} ->
        %{
          jsonrpc: "2.0",
          error: %{code: code, message: message},
          id: id
        }
    end
  end

  # Handle invalid JSON-RPC requests
  def handle_request(_, _) do
    %{
      jsonrpc: "2.0",
      error: %{code: -32600, message: "Invalid Request"},
      id: nil
    }
  end

  # Handle specific RPC methods
  defp handle_method("parameters", [], _websocket_pid) do
    {:ok, get_parameters()}
  end

  defp handle_method("bestBlock", [], _websocket_pid) do
    case get_best_block() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, -32603, "Internal error: #{reason}"}
    end
  end

  defp handle_method("subscribeBestBlock", [], websocket_pid) when websocket_pid != nil do
    subscription_id = SubscriptionManager.create_subscription("bestBlock", [], websocket_pid)
    {:subscription, subscription_id}
  end

  defp handle_method("finalizedBlock", [], _websocket_pid) do
    case get_finalized_block() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, -32603, "Internal error: #{reason}"}
    end
  end

  defp handle_method("subscribeFinalizedBlock", [], websocket_pid) when websocket_pid != nil do
    subscription_id = SubscriptionManager.create_subscription("finalizedBlock", [], websocket_pid)
    {:subscription, subscription_id}
  end

  # Handle subscription methods called via HTTP (should return error)
  defp handle_method("subscribe" <> _rest, _params, nil) do
    {:error, -32601, "Subscriptions are only available via WebSocket"}
  end

  # Method not found
  defp handle_method(method, params, _websocket_pid) do
    Log.debug("Invalid RPC call: #{method} #{inspect(params)}")
    {:error, -32601, "Method not found: #{method}"}
  end

  # Implementation functions

  defp get_parameters do
    # Return JAM chain parameters according to JIP-2 spec
    params = %{
      # B_S
      "deposit_per_account" => Constants.service_minimum_balance(),
      # B_I
      "deposit_per_item" => Constants.additional_minimum_balance_per_item(),
      # B_L
      "deposit_per_byte" => Constants.additional_minimum_balance_per_octet(),
      # C
      "core_count" => Constants.core_count(),
      # D
      "min_turnaround_period" => Constants.forget_delay(),
      # E
      "epoch_period" => Constants.epoch_length(),
      # G_A
      "max_accumulate_gas" => Constants.gas_accumulation(),
      # G_I
      "max_is_authorized_gas" => Constants.gas_is_authorized(),
      # G_R
      "max_refine_gas" => Constants.gas_refine(),
      # G_T
      "block_gas_limit" => Constants.gas_total_accumulation(),
      # H
      "recent_block_count" => Constants.recent_history_size(),
      # I
      "max_work_items" => Constants.max_work_items(),
      # J
      "max_dependencies" => Constants.max_work_report_dep_sum(),
      # K
      "max_tickets_per_block" => Constants.max_tickets_pre_extrinsic(),
      # L
      "max_lookup_anchor_age" => Constants.max_age_lookup_anchor(),
      # N
      "tickets_attempts_number" => Constants.tickets_per_validator(),
      # O
      "auth_window" => Constants.max_authorizations_items(),
      # P
      "slot_period_sec" => Constants.slot_period(),
      # Q
      "auth_queue_len" => Constants.max_authorization_queue_items(),
      # R
      "rotation_period" => Constants.rotation_period(),
      # T
      "max_extrinsics" => Constants.max_extrinsics(),
      # U
      "availability_timeout" => Constants.unavailability_period(),
      # V
      "val_count" => Constants.validator_count(),
      # W_A
      "max_authorizer_code_size" => Constants.max_authorizer_code_size(),
      # W_B
      "max_input" => Constants.max_work_package_size(),
      # W_C
      "max_service_code_size" => Constants.max_service_code_size(),
      # W_E
      "basic_piece_len" => Constants.erasure_coded_piece_size(),
      # W_M
      "max_imports" => Constants.max_imports(),
      # W_P
      "segment_piece_count" => Constants.erasure_coded_pieces_per_segment(),
      # W_T
      "transfer_memo_size" => Constants.memo_size(),
      # W_X
      "max_exports" => Constants.max_exports(),
      # max_refine_memory - not in Constants, keeping as hardcoded for now
      "max_refine_memory" => 1_073_741_824,
      # max_is_authorized_memory - not in Constants, keeping as hardcoded for now
      "max_is_authorized_memory" => 1_073_741_824,
      # UNKNOWN BUT REQUIRED BY jamtop
      "max_report_elective_data" => 0,
      "epoch_tail_start" => 0
    }

    %{"V1" => params}
  end

  def get_best_block do
    try do
      case Storage.get_latest_header() do
        {_timeslot, header} ->
          hash = h(e(header))

          {:ok, [hash |> :binary.bin_to_list(), header.timeslot]}

        nil ->
          # Return genesis block if no blocks are available
          genesis_header = Jamixir.Genesis.genesis_block_header()
          hash = Jamixir.Genesis.genesis_header_hash()

          {:ok, [hash |> :binary.bin_to_list(), genesis_header.timeslot]}
      end
    catch
      error -> {:error, "Failed to get best block: #{inspect(error)}"}
    end
  end

  # For now, we'll use the same as best block since finalization isn't fully implemented
  # In a real implementation, you'd track finalized blocks separately
  defp get_finalized_block, do: get_best_block()
end
