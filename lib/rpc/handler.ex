defmodule Jamixir.RPC.Handler do
  @moduledoc """
  Main RPC handler that processes JSON-RPC method calls according to JIP-2 specification.
  """

  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.WorkPackage
  alias Codec.State.Trie
  alias Jamixir.Node
  alias Jamixir.RPC.SubscriptionManager
  alias Network.ConnectionManager
  import Codec.Encoder
  import Util.Hex

  @log_context "[RPC]"
  use Util.Logger

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

    debug("🔧 Processing method: #{method}")
    params = if method =~ ~r/^unsubscribe/, do: params, else: decode_64_params(params)

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

  def handle_request(_, _) do
    %{
      jsonrpc: "2.0",
      error: %{code: -32_600, message: "Invalid Request"},
      id: nil
    }
  end

  defp handle_method("parameters", [], _websocket_pid) do
    {:ok, get_parameters()}
  end

  defp handle_method("bestBlock", [], _websocket_pid) do
    case get_best_block() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, -32603, "Internal error: #{reason}"}
    end
  end

  defp handle_method("parent", [header_hash], _) do
    debug("call: parent #{b16(header_hash)}")
    {:ok, blocks} = Node.get_blocks(header_hash, :descending, 2)

    debug("Found #{length(blocks)} blocks")

    {:ok,
     case blocks do
       [_, %Block{header: h}] -> [e64(h(e(h))), h.timeslot]
       _ -> nil
     end}
  end

  defp handle_method("stateRoot", [header_hash], _websocket_pid) do
    state = Jamixir.NodeAPI.inspect_state(header_hash)

    {:ok,
     case state do
       {:error, :no_state} -> nil
       {:ok, s} -> e64(Trie.state_root(s))
     end}
  end

  defp handle_method("statistics", [header_hash], _websocket_pid) do
    {:ok, state} = Jamixir.NodeAPI.inspect_state(header_hash)
    {:ok, e64(e(state.validator_statistics))}
  end

  defp handle_method("serviceData", [header_hash, service_id], _websocket_pid) do
    {:ok, state} = Jamixir.NodeAPI.inspect_state(header_hash)
    {:ok, e64(e(state.services[service_id]))}
  end

  defp handle_method("subscribeServiceRequest", [service_id, hash, len, finalized], websocket_pid)
       when websocket_pid != nil do
    debug("serviceRequest subscription service=#{service_id}, hash=#{b16(hash)}, len=#{len}")

    params = [service_id, hash, len, finalized]

    id = SubscriptionManager.create_subscription("serviceRequest", params, websocket_pid)

    {:subscription, id}
  end

  defp handle_method("subscribeServiceValue", [service_id, key, _finalized], websocket_pid)
       when websocket_pid != nil do
    debug("serviceValue subscription service=#{service_id}, key=#{b16(key)}")

    params = [service_id, key]

    id = SubscriptionManager.create_subscription("serviceValue", params, websocket_pid)

    {:subscription, id}
  end

  defp handle_method("servicePreimage", [header_hash, service_id, hash], _websocket_pid) do
    {:ok, state} = Jamixir.NodeAPI.inspect_state(header_hash)

    case get_in(state.services, [service_id, :preimage_storage_p, hash]) do
      nil -> {:ok, nil}
      preimage -> {:ok, e64(preimage)}
    end
  end

  defp handle_method("serviceRequest", [header_hash, service_id, hash, length], _websocket_pid) do
    {:ok, state} = Jamixir.NodeAPI.inspect_state(header_hash)

    debug(
      "serviceRequest call for header_hash=#{b16(header_hash)} service_id=#{service_id}, hash=#{b16(hash)}, length=#{length}"
    )

    case get_in(state.services, [service_id, :storage, {hash, length}]) do
      nil -> {:ok, nil}
      slots -> {:ok, slots}
    end
  end

  defp handle_method("beefyRoot", [header_hash], _websocket_pid) do
    {_timeslot, header} = Storage.get_latest_header()
    {:ok, state} = Jamixir.NodeAPI.inspect_state(h(e(header)))

    hash = header_hash

    {:ok,
     case Enum.find(state.recent_history.blocks, fn rb -> rb.header_hash == hash end) do
       nil -> nil
       b -> e64(b.beefy_root)
     end}
  end

  defp handle_method("submitPreimage", [service_id, blob], _websocket_pid) do
    bin = blob
    hash = h(bin)
    log("Submitting preimage service #{service_id} hash #{b16(hash)} of size #{byte_size(bin)}")
    preimage = %Preimage{blob: bin, service: service_id}
    :ok = Jamixir.NodeAPI.save_preimage(preimage)

    Task.async(fn ->
      # TODO announce only to neighbours instead of all
      for {_, pid} <- ConnectionManager.instance().get_connections() do
        Network.Connection.announce_preimage(pid, preimage)
      end
    end)

    {:ok, nil}
  end

  defp handle_method("submitWorkPackage", [core, blob, extrinsics], _websocket_pid) do
    {wp, _} = WorkPackage.decode(blob)
    Logger.debug("WP blob: #{b16(blob)}")
    ext_bins = for e <- extrinsics, do: e
    :ok = Jamixir.NodeAPI.save_work_package(wp, core, ext_bins)

    {:ok, nil}
  end

  defp handle_method("serviceValue", [header_hash, service_id, hash], _websocket_pid) do
    header_hash = header_hash
    hash = hash
    {:ok, state} = Jamixir.NodeAPI.inspect_state(header_hash)

    {:ok,
     case get_in(state.services, [service_id, :storage, hash]) do
       nil ->
         nil

       value ->
         debug("serviceValue #{service_id} hash: #{b16(hash)} value: #{b16(value)}")
         e64(value)
     end}
  end

  defp handle_method("finalizedBlock", [], _websocket_pid) do
    case get_finalized_block() do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, -32603, "Internal error: #{reason}"}
    end
  end

  defp handle_method("listServices", [header_hash], _websocket_pid) do
    {:ok, state} = Jamixir.NodeAPI.inspect_state(header_hash)
    {:ok, Map.keys(state.services)}
  end

  defp handle_method("unsubscribe" <> _rest, [id], _) do
    case SubscriptionManager.unsubscribe(id) do
      :ok -> {:ok, true}
      :error -> {:ok, false}
    end
  end

  defp handle_method("syncStatus", params, pid), do: handle_method("syncState", params, pid)

  defp handle_method("syncState", [], nil) do
    {:ok,
     %{"num_peers" => map_size(ConnectionManager.get_connections()), "status" => "Completed"}}
  end

  # Handle subscription methods called via HTTP (should return error)
  defp handle_method("subscribe" <> method, params, websocket_pid)
       when method != "" and websocket_pid != nil do
    first = String.first(method)
    method = String.replace_prefix(method, first, String.downcase(first))

    subscription_id = SubscriptionManager.create_subscription(method, params, websocket_pid)
    {:subscription, subscription_id}
  end

  # Method not found
  defp handle_method(method, params, _websocket_pid) do
    debug("Invalid call: #{method} #{inspect(params)}")
    {:error, -32601, "Method not found: #{method}"}
  end

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
          hash = e64(h(e(header)))

          {:ok, [hash, header.timeslot]}

        nil ->
          # Return genesis block if no blocks are available
          genesis_header = Jamixir.Genesis.genesis_block_header()
          hash = e64(Jamixir.Genesis.genesis_header_hash())

          {:ok, [hash, genesis_header.timeslot]}
      end
    catch
      error -> {:error, "Failed to get best block: #{inspect(error)}"}
    end
  end

  # For now, we'll use the same as best block since finalization isn't fully implemented
  defp get_finalized_block, do: get_best_block()

  defp decode_64_params(params) when is_list(params),
    do: for(p <- params, do: decode_64_params(p))

  defp decode_64_params(param) when is_binary(param), do: d64(param)
  defp decode_64_params(param), do: param
end
