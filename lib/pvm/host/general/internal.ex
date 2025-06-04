# Formula (B.18) v0.6.6
defmodule PVM.Host.General.Internal do
  import PVM.{Constants.HostCallResult}
  alias Block.Extrinsic.WorkPackage
  alias System.DeferredTransfer
  alias Block.Extrinsic.WorkItem
  alias PVM.Accumulate.Operand
  alias PVM.Host.General.Result
  alias PVM.{Memory, Registers}
  alias System.State.ServiceAccount
  alias Util.Hash
  import Codec.Encoder
  import PVM.Host.Util
  import Constants
  require Logger

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}
  @max_64_bit_value 0xFFFF_FFFF_FFFF_FFFF

  @spec fetch_internal(
          Registers.t(),
          Memory.t(),
          # context
          any(),
          WorkPackage | nil,
          binary() | nil,
          binary() | nil,
          non_neg_integer() | nil,
          list(list(binary())) | nil,
          list(list(binary())) | nil,
          list(Operand.t()) | nil,
          list(DeferredTransfer.t()) | nil
        ) :: Result.Internal.t()
  def fetch_internal(
        registers,
        memory,
        context,
        work_package,
        n,
        authorizer_output,
        service_index,
        import_segments,
        preimages,
        operands,
        transfers
      ) do
    [w10, w11, w12] = Registers.get(registers, [10, 11, 12])

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
            # E4(L)
            max_age_lookup_anchor()::m(timeslot),
            # E2(O)
            max_authorizations_items()::16-little,
            # E2(P)
            slot_period()::16-little,
            # E2(Q)
            max_authorization_queue_items()::16-little,
            # E2(R)
            rotation_period()::16-little,
            # E2(S)
            max_accumulation_queue_items()::16-little,
            # E2(T)
            max_extrinsics()::16-little,
            # E2(U)
            unavailability_period()::16-little,
            # E2(V)
            validator_count()::16-little,
            # E4(W_A)
            max_is_authorized_code_size()::32-little,
            # E4(W_B)
            max_work_package_size()::32-little,
            # E4(W_C)
            max_service_code_size()::32-little,
            # E4(W_E)
            erasure_coded_piece_size()::32-little,
            # E4(W_G)
            segment_size()::32-little,
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

        authorizer_output != nil and w10 == 2 ->
          authorizer_output

        service_index != nil and w10 == 3 and w11 < length(preimages) and
            w12 < length(Enum.at(preimages, w11)) ->
          preimages |> Enum.at(w11) |> Enum.at(w12)

        service_index != nil and w10 == 4 and w11 < length(Enum.at(preimages, service_index)) ->
          preimages |> Enum.at(service_index) |> Enum.at(w11)

        service_index != nil and w10 == 5 and w11 < length(import_segments) and
            w12 < length(Enum.at(import_segments, w11)) ->
          import_segments |> Enum.at(w11) |> Enum.at(w12)

        service_index != nil and w10 == 6 and
            w11 < length(Enum.at(import_segments, service_index)) ->
          import_segments |> Enum.at(service_index) |> Enum.at(w11)

        work_package != nil and w10 == 7 ->
          e(work_package)

        work_package != nil and w10 == 8 ->
          e({work_package.authorization_code_hash, vs(work_package.parameterization_blob)})

        work_package != nil and w10 == 9 ->
          work_package.authorization_token

        work_package != nil and w10 == 10 ->
          e(work_package.context)

        work_package != nil and w10 == 11 ->
          e(vs(for wi <- work_package.work_items, do: WorkItem.encode_for_fetch_host_call(wi)))

        work_package != nil and w10 == 12 and w11 < length(work_package.work_items) ->
          WorkItem.encode_for_fetch_host_call(Enum.at(work_package.work_items, w11))

        work_package != nil and w10 == 13 and w11 < length(work_package.work_items) ->
          work_package.work_items |> Enum.at(w11) |> Map.get(:payload)

        operands != nil and w10 == 14 ->
          e(vs(operands))

        operands != nil and w10 == 15 and w11 < length(operands) ->
          e(Enum.at(operands, w11))

        transfers != nil and w10 == 16 ->
          e(vs(transfers))

        transfers != nil and w10 == 17 and w11 < length(transfers) ->
          e(Enum.at(transfers, w11))

        true ->
          nil
      end

    [o, w8, w9] = Registers.get(registers, [7, 8, 9])
    f = min(w8, safe_byte_size(v))
    l = min(w9, safe_byte_size(v) - f)

    is_writable = Memory.check_range_access?(memory, o, l, :write)

    {exit_reason_, w7_, memory__} =
      cond do
        !is_writable ->
          {:panic, registers.r7, memory}

        is_nil(v) ->
          {:continue, none(), memory}

        true ->
          {:continue, byte_size(v), Memory.write!(memory, o, binary_part(v, f, l))}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory__,
      context: context
    }
  end

  @spec lookup_internal(Registers.t(), Memory.t(), ServiceAccount.t(), integer(), services()) ::
          Result.Internal.t()
  def lookup_internal(registers, memory, service_account, service_index, services) do
    a =
      if registers.r7 in [@max_64_bit_value, service_index],
        do: service_account,
        else: Map.get(services, registers.r7)

    [h, o] = Registers.get(registers, [8, 9])

    v =
      try do
        pre_image_hash = Memory.read!(memory, h, 32)

        if is_nil(a), do: nil, else: Map.get(a, :preimage_storage_p) |> Map.get(pre_image_hash)
      rescue
        _ -> :error
      end

    f = min(registers.r10, safe_byte_size(v))
    l = min(registers.r11, safe_byte_size(v) - f)

    is_writable = Memory.check_range_access?(memory, o, l, :write)

    {exit_reason_, w7_, memory__} =
      cond do
        v == :error or !is_writable ->
          {:panic, registers.r7, memory}

        is_nil(v) ->
          {:continue, none(), memory}

        true ->
          {:continue, byte_size(v), Memory.write!(memory, o, binary_part(v, f, l))}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory__,
      context: service_account
    }
  end

  @spec read_internal(Registers.t(), Memory.t(), ServiceAccount.t(), integer(), %{
          non_neg_integer() => ServiceAccount.t()
        }) ::
          Result.Internal.t()
  def read_internal(registers, memory, service_account, service_index, services) do
    s_star =
      cond do
        registers.r7 == @max_64_bit_value -> service_index
        true -> registers.r7
      end

    a =
      cond do
        s_star == service_index -> service_account
        true -> Map.get(services, s_star)
      end

    [ko, kz, o] = Registers.get(registers, [8, 9, 10])

    storage_key =
      try do
        (<<s_star::service()>> <> Memory.read!(memory, ko, kz)) |> Hash.default()
      rescue
        _ -> :error
      end

    v =
      cond do
        storage_key == :error -> :error
        a != nil -> Map.get(a.storage, storage_key)
        true -> nil
      end

    f = min(registers.r11, safe_byte_size(v))
    l = min(registers.r12, safe_byte_size(v) - f)

    is_writable = Memory.check_range_access?(memory, o, l, :write)

    {exit_reason_, w7_, memory__} =
      cond do
        v == :error or !is_writable ->
          {:panic, registers.r7, memory}

        v == nil ->
          {:continue, none(), memory}

        true ->
          {:continue, byte_size(v), Memory.write!(memory, o, binary_part(v, f, l))}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory__,
      context: service_account
    }
  end

  @spec write_internal(
          Registers.t(),
          Memory.t(),
          ServiceAccount.t(),
          non_neg_integer()
        ) ::
          Result.Internal.t()
  def write_internal(registers, memory, service_account, service_index) do
    [ko, kz, vo, vz] = Registers.get(registers, [7, 8, 9, 10])

    k = read_storage_key(memory, ko, kz, service_index)

    a =
      cond do
        k != :error and vz == 0 ->
          storage_ = Map.get(service_account, :storage) |> Map.drop([k])
          put_in(service_account, [:storage], storage_)

        k != :error ->
          try do
            value = Memory.read!(memory, vo, vz)
            put_in(service_account, [:storage, k], value)
          rescue
            _ -> :error
          end

        true ->
          :error
      end

    l = current_value_length(k, service_account)

    {exit_reason_, w7_, service_account_} =
      cond do
        k == :error or a == :error -> {:panic, registers.r7, service_account}
        ServiceAccount.threshold_balance(a) > a.balance -> {:continue, full(), service_account}
        true -> {:continue, l, a}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: service_account_
    }
  end

  defp read_storage_key(memory, ko, kz, service_id) do
    try do
      (t(service_id) <> Memory.read!(memory, ko, kz)) |> Hash.default()
    rescue
      _ -> :error
    end
  end

  defp current_value_length(:error, _service_account), do: none()

  defp current_value_length(k, service_account) do
    if k in Map.keys(service_account.storage),
      do: safe_byte_size(get_in(service_account, [:storage, k])),
      else: none()
  end

  @spec info_internal(Registers.t(), Memory.t(), ServiceAccount.t(), integer(), services()) ::
          Result.Internal.t()
  def info_internal(registers, memory, context, service_index, services) do
    t =
      if registers.r7 == @max_64_bit_value,
        do: services[service_index],
        else: services[registers.r7]

    o = registers.r8

    m =
      if t != nil do
        e(
          {t.code_hash, t.balance, ServiceAccount.threshold_balance(t), t.gas_limit_g,
           t.gas_limit_m, ServiceAccount.octets_in_storage(t), ServiceAccount.items_in_storage(t)}
        )
      else
        nil
      end

    is_writable = Memory.check_range_access?(memory, o, safe_byte_size(m), :write)

    memory_ =
      if m != nil and is_writable do
        Memory.write!(memory, o, m)
      else
        memory
      end

    {exit_reason_, w7_} =
      cond do
        m == nil ->
          {:continue, none()}

        m != nil and !is_writable ->
          {:panic, registers.r7}

        true ->
          {:continue, ok()}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory_,
      context: context
    }
  end

  @spec log_internal(Registers.t(), Memory.t(), any(), integer() | nil, integer() | nil) ::
          Result.Internal.t()
  def log_internal(registers, memory, context, core_index, service_index) do
    [log_level, target_addr, target_len, message_addr, message_len] =
      Registers.get(registers, [7, 8, 9, 10, 11])

    target =
      if target_len == 0 and target_addr == 0 do
        ""
      else
        case Memory.read(memory, target_addr, target_len) do
          {:ok, target} -> target
          {:error, _} -> :error
        end
      end

    message =
      case Memory.read(memory, message_addr, message_len) do
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
      memory: memory,
      context: context
    }
  end

  # According to https://github.com/polkadot-fellows/JIPs/pull/6/files
  defp print_log_message(log_level, target, message, core_index, service_index) do
    # Format timestamp
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    timestamp =
      :io_lib.format(
        "~4..0w/~2..0w/~2..0w ~2..0w:~2..0w:~2..0w",
        [year, month, day, hour, minute, second]
      )

    target = if target != "", do: " [#{target}]", else: ""

    message =
      "#{timestamp}#{prefixed(core_index, "@")}#{prefixed(service_index, "#")}#{target} #{message}"

    level =
      %{0 => :debug, 1 => :debug, 2 => :info, 3 => :warning, 4 => :error}[log_level] || :info

    Logger.bare_log(level, message)
  end

  defp prefixed(s, prefix), do: if(s != nil, do: "#{prefix}#{s}", else: "")
end
