defmodule PVM.Host.General.Internal do
  import PVM.{Constants.HostCallResult}
  alias Block.Extrinsic.WorkItem
  alias Block.Extrinsic.WorkPackage
  alias PVM.Host.General.Result
  alias PVM.Registers
  alias System.State.ServiceAccount
  import Codec.Encoder
  import PVM.Host.Util
  import Constants
  import Util.Hex
  import Pvm.Native

  @log_context "[PVM]"
  use Util.Logger

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}
  @max_64_bit_value 0xFFFF_FFFF_FFFF_FFFF

  # Formula (B.16) v0.7.2
  @spec fetch_internal(
          Registers.t(),
          reference(),
          # context
          any(),
          WorkPackage | nil,
          binary() | nil,
          binary() | nil,
          non_neg_integer() | nil,
          list(list(binary())) | nil,
          list(list(binary())) | nil,
          list(Types.accumulation_input()) | nil
        ) :: Result.Internal.t()
  def fetch_internal(
        registers,
        memory_ref,
        context,
        work_package,
        n,
        authorizer_trace,
        service_index,
        import_segments,
        extrinsics,
        accumulation_inputs
      ) do
    {w10, w11, w12} = Registers.get_3(registers, 10, 11, 12)

    v =
      cond do
        w10 == 0 ->
          <<
            # E8(B_I)
            additional_minimum_balance_per_item()::m(balance),
            # E8(B_L)
            additional_minimum_balance_per_octet()::m(balance),
            # E8(B_S)
            service_minimum_balance()::m(balance),
            # E2(C)
            core_count()::m(core_index),
            # E4(D)
            forget_delay()::m(timeslot),
            # E4(E)
            epoch_length()::m(epoch),
            # E8(G_A)
            gas_accumulation()::m(gas),
            # E8(G_I)
            gas_is_authorized()::m(gas),
            # E8(G_R)
            gas_refine()::m(gas),
            # E8(G_T)
            gas_total_accumulation()::m(gas),
            # E2(H)
            recent_history_size()::16-little,
            # E2(I)
            max_work_items()::16-little,
            # E2(J)
            max_work_report_dep_sum()::16-little,
            # E2(K)
            max_tickets_pre_extrinsic()::16-little,
            # E4(L)
            max_age_lookup_anchor()::m(timeslot),
            # E2(N)
            tickets_per_validator()::16-little,
            # E2(O)
            max_authorizations_items()::16-little,
            # E2(P)
            slot_period()::16-little,
            # E2(Q)
            max_authorization_queue_items()::16-little,
            # E2(R)
            rotation_period()::16-little,
            # E2(T)
            max_extrinsics()::16-little,
            # E2(U)
            unavailability_period()::16-little,
            # E2(V)
            validator_count()::16-little,
            # E4(W_A)
            max_authorizer_code_size()::32-little,
            # E4(W_B)
            max_work_package_size()::32-little,
            # E4(W_C)
            max_service_code_size()::32-little,
            # E4(W_E)
            erasure_coded_piece_size()::32-little,
            # E4(W_M)
            max_imports()::32-little,
            # E4(W_P)
            erasure_coded_pieces_per_segment()::32-little,
            # E4(W_R)
            max_work_report_size()::32-little,
            # E4(W_T)
            memo_size()::32-little,
            # E4(W_X)
            max_exports()::32-little,
            # E4(Y)
            ticket_submission_end()::32-little
          >>

        n != nil and w10 == 1 ->
          n

        authorizer_trace != nil and w10 == 2 ->
          authorizer_trace

        extrinsics != nil and w10 == 3 and w11 < length(extrinsics) and
            w12 < length(Enum.at(extrinsics, w11)) ->
          extrinsics |> Enum.at(w11) |> Enum.at(w12)

        extrinsics != nil and service_index != nil and w10 == 4 and
            w11 < length(Enum.at(extrinsics, service_index)) ->
          extrinsics |> Enum.at(service_index) |> Enum.at(w11)

        import_segments != nil and w10 == 5 and w11 < length(import_segments) and
            w12 < length(Enum.at(import_segments, w11)) ->
          import_segments |> Enum.at(w11) |> Enum.at(w12)

        import_segments != nil and service_index != nil and w10 == 6 and
            w11 < length(Enum.at(import_segments, service_index)) ->
          import_segments |> Enum.at(service_index) |> Enum.at(w11)

        work_package != nil and w10 == 7 ->
          e(work_package)

        work_package != nil and w10 == 8 ->
          work_package.parameterization_blob

        work_package != nil and w10 == 9 ->
          work_package.authorization_token

        work_package != nil and w10 == 10 ->
          e(work_package.context)

        work_package != nil and w10 == 11 ->
          e(vs(for wi <- work_package.work_items, do: WorkItem.encode(wi, :fetch_host_call)))

        work_package != nil and w10 == 12 and w11 < length(work_package.work_items) ->
          WorkItem.encode(Enum.at(work_package.work_items, w11), :fetch_host_call)

        work_package != nil and w10 == 13 and w11 < length(work_package.work_items) ->
          work_package.work_items |> Enum.at(w11) |> Map.get(:payload)

        accumulation_inputs != nil and w10 == 14 ->
          e(vs(accumulation_inputs))

        accumulation_inputs != nil and w10 == 15 and w11 < length(accumulation_inputs) ->
          e(Enum.at(accumulation_inputs, w11))

        true ->
          nil
      end

    {w7, w8, w9} = Registers.get_3(registers, 7, 8, 9)
    o = w7
    f = min(w8, safe_byte_size(v))
    l = min(w9, safe_byte_size(v) - f)

    {exit_reason_, w7_} =
      cond do
        is_nil(v) ->
          {:continue, none()}

        true ->
          value = binary_part(v, f, l)

          case memory_write(memory_ref, o, value) do
            {:ok, _} ->
              {:continue, byte_size(v)}

            {:error, _} ->
              {:panic, w7}
          end
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context
    }
  end

  @spec lookup_internal(Registers.t(), reference(), ServiceAccount.t(), integer(), services()) ::
          Result.Internal.t()
  def lookup_internal(registers, memory_ref, service_account, service_index, services) do
    {w7, h, o, w10, w11} = Registers.get_5(registers, 7, 8, 9, 10, 11)

    a =
      if w7 in [@max_64_bit_value, service_index],
        do: service_account,
        else: Map.get(services, w7)

    v =
      case memory_read(memory_ref, h, 32) do
        {:ok, pre_image_hash} ->
          if is_nil(a), do: nil, else: Map.get(a, :preimage_storage_p) |> Map.get(pre_image_hash)

        {:error, _} ->
          :error
      end

    f = min(w10, safe_byte_size(v))
    l = min(w11, safe_byte_size(v) - f)

    {exit_reason_, w7_} =
      cond do
        v == :error ->
          {:panic, w7}

        is_nil(v) ->
          {:continue, none()}

        true ->
          value = binary_part(v, f, l)

          case memory_write(memory_ref, o, value) do
            {:ok, _} ->
              {:continue, byte_size(v)}

            {:error, _} ->
              {:panic, w7}
          end
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: service_account
    }
  end

  @spec read_internal(Registers.t(), reference(), ServiceAccount.t(), integer(), %{
          non_neg_integer() => ServiceAccount.t()
        }) ::
          Result.Internal.t()
  def read_internal(registers, memory_ref, service_account, service_index, services) do
    w7 = registers[7]
    s_star = if w7 == @max_64_bit_value, do: service_index, else: w7
    a = if s_star == service_index, do: service_account, else: Map.get(services, s_star)

    {ko, kz, o, w11, w12} = Registers.get_5(registers, 8, 9, 10, 11, 12)

    storage_key = read_storage_key(memory_ref, ko, kz)

    v =
      cond do
        storage_key == :error -> :error
        a != nil -> get_in(a, [:storage, storage_key])
        true -> nil
      end

    f = min(w11, safe_byte_size(v))
    l = min(w12, safe_byte_size(v) - f)

    {exit_reason_, w7_} =
      cond do
        v == :error ->
          {:panic, w7}

        v == nil ->
          {:continue, none()}

        true ->
          value = binary_part(v, f, l)

          case memory_write(memory_ref, o, value) do
            {:ok, _} ->
              {:continue, byte_size(v)}

            {:error, _} ->
              {:panic, w7}
          end
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: service_account
    }
  end

  @spec write_internal(
          Registers.t(),
          reference(),
          ServiceAccount.t(),
          non_neg_integer()
        ) ::
          Result.Internal.t()
  def write_internal(registers, memory_ref, service_account, service_id) do
    {w7, kz, vo, vz} = Registers.get_4(registers, 7, 8, 9, 10)
    ko = w7

    k = read_storage_key(memory_ref, ko, kz)

    a =
      case k do
        :error ->
          :error

        _ when vz == 0 ->
          {_, sa} = pop_in(service_account, [:storage, k])
          log(:debug, "Deleted storage key: #{b16(k)} [id: #{service_id}]")
          log(:debug, "Now storage has #{inspect(sa.storage.items_in_storage)} items")
          sa

        _ ->
          case memory_read(memory_ref, vo, vz) do
            {:ok, value} ->
              log(:debug, "Write to storage key #{b16(k)} => #{b16(value)} [id: #{service_id}]")

              sa = put_in(service_account, [:storage, k], value)
              log(:debug, "Now storage has #{inspect(sa.storage.items_in_storage)} items")
              sa

            {:error, _} ->
              :error
          end
      end

    l = current_value_length(k, service_account)

    {exit_reason_, w7_, service_account_} =
      cond do
        k == :error or a == :error -> {:panic, w7, service_account}
        ServiceAccount.threshold_balance(a) > a.balance -> {:continue, full(), service_account}
        true -> {:continue, l, a}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: service_account_
    }
  end

  defp read_storage_key(memory_ref, ko, kz) do
    case memory_read(memory_ref, ko, kz) do
      {:ok, data} -> data
      {:error, _} -> :error
    end
  end

  defp current_value_length(:error, _service_account), do: none()

  defp current_value_length(k, service_account) do
    if HashedKeysMap.has_key?(service_account.storage, k),
      do: safe_byte_size(get_in(service_account, [:storage, k])),
      else: none()
  end

  @spec info_internal(Registers.t(), reference(), ServiceAccount.t(), integer(), services()) ::
          Result.Internal.t()
  def info_internal(registers, memory_ref, context, service_index, services) do
    {w7, w8, w9, w10} = Registers.get_4(registers, 7, 8, 9, 10)

    a =
      if w7 == @max_64_bit_value,
        do: services[service_index],
        else: services[w7]

    o = w8

    v =
      if a != nil do
        <<
          a.code_hash::binary,
          a.balance::m(balance),
          ServiceAccount.threshold_balance(a)::m(balance),
          a.gas_limit_g::m(gas),
          a.gas_limit_m::m(gas),
          a.storage.octets_in_storage::64-little,
          a.storage.items_in_storage::32-little,
          a.deposit_offset::64-little,
          a.creation_slot::m(timeslot),
          a.last_accumulation_slot::m(timeslot),
          a.parent_service::service()
        >>
      else
        nil
      end

    f = min(w9, safe_byte_size(v))
    l = min(w10, safe_byte_size(v) - f)

    {exit_reason_, w7_} =
      cond do
        v == nil ->
          {:continue, none()}

        true ->
          value = binary_part(v, f, l)

          case memory_write(memory_ref, o, value) do
            {:ok, _} ->
              {:continue, byte_size(v)}

            {:error, _} ->
              {:panic, w7}
          end
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context
    }
  end

  @spec log_internal(Registers.t(), reference(), any(), integer() | nil, integer() | nil) ::
          Result.Internal.t()
  def log_internal(registers, memory_ref, context, core_index, service_index) do
    {log_level, target_addr, target_len, message_addr, message_len} =
      Registers.get_5(registers, 7, 8, 9, 10, 11)

    target =
      if target_len == 0 and target_addr == 0 do
        ""
      else
        case memory_read(memory_ref, target_addr, target_len) do
          {:ok, target} -> target
          {:error, _} -> :error
        end
      end

    message =
      case memory_read(memory_ref, message_addr, message_len) do
        {:ok, message} -> message
        {:error, _} -> :error
      end

    if target != :error and message != :error do
      print_log_message(log_level, target, message, core_index, service_index)
    end

    # Return original registers unchanged
    %Result.Internal{
      exit_reason: :continue,
      registers: registers,
      context: context
    }
  end

  # According to https://github.com/polkadot-fellows/JIPs/pull/6/files
  defp print_log_message(_log_level, target, message, core_index, service_index) do
    # Format timestamp

    target = if target != "", do: " [#{target}]", else: ""

    message = "#{prefixed(core_index, "@")}#{prefixed(service_index, "#")}#{target} #{message}"

    # PVM log will always be DEBUG
    log(:debug, message)
  end

  defp prefixed(s, prefix), do: if(s != nil, do: "#{prefix}#{s}", else: "")
end
