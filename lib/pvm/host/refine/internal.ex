# Formula (B.22) v0.6.0
defmodule PVM.Host.Refine.Internal do
  alias Block.Extrinsic.WorkPackage
  alias System.State.ServiceAccount
  alias PVM.{Host.Refine.Context, Host.Refine.Result.Internal, Integrated, Memory, Registers}
  use Codec.{Decoder, Encoder}
  import PVM.{Constants.HostCallResult, Constants.InnerPVMResult, Host.Util}
  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  @spec historical_lookup_internal(
          Registers.t(),
          Memory.t(),
          Context.t(),
          non_neg_integer(),
          services(),
          non_neg_integer()
        ) :: Internal.t()
  def historical_lookup_internal(registers, memory, context, index, service_accounts, timeslot) do
    w7 = registers.r7

    a =
      cond do
        w7 == 0xFFFF_FFFF_FFFF_FFFF and Map.has_key?(service_accounts, index) ->
          Map.get(service_accounts, index)

        Map.has_key?(service_accounts, w7) ->
          Map.get(service_accounts, w7)

        true ->
          nil
      end

    [h, o] = Registers.get(registers, [8, 9])

    v =
      try do
        hash = PVM.Memory.read!(memory, h, 32)

        case a do
          nil -> nil
          _ -> ServiceAccount.historical_lookup(a, timeslot, hash)
        end
      rescue
        _ -> :error
      end

    f = min(registers.r10, safe_byte_size(v))
    l = min(registers.r11, safe_byte_size(v) - f)
    is_writable = Memory.check_range_access?(memory, o, l, :write)

    {exit_reason, w7_, memory_} =
      cond do
        v == :error or not is_writable ->
          {:panic, registers.r7, memory}

        v == nil ->
          {:continue, none(), memory}

        true ->
          {:continue, byte_size(v), Memory.write!(memory, o, binary_part(v, f, l))}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory_,
      context: context
    }
  end

  # see here about where the preimages comes from , it is not in the GP
  # but knowledge of it is assume,
  # this is a repeating pattern in refine logic (in-core, off-chain)
  # it is up to us to figure out what data/maps we are to store and where/when to store it
  # https://matrix.to/#/!ddsEwXlCWnreEGuqXZ:polkadot.io/$2BY5KB1iDMI3RxikTBLj0iMYJbf7L5EhZjXl0xRKlBw?via=polkadot.io&via=matrix.org&via=parity.io
  @spec fetch_internal(
          Registers.t(),
          Memory.t(),
          Context.t(),
          non_neg_integer(),
          WorkPackage.t(),
          binary(),
          list(list(binary())),
          %{{Types.hash(), non_neg_integer()} => binary()}
        ) :: Internal.t()
  def fetch_internal(
        registers,
        memory,
        context,
        work_item_index,
        work_package,
        authorizer_output,
        import_segments,
        preimages
      ) do
    [w9, w10, w11, w12] = Registers.get(registers, [9, 10, 11, 12])

    v =
      cond do
        w10 == 0 ->
          e(work_package)

        w10 == 1 ->
          authorizer_output

        w10 == 2 and w11 < length(work_package.work_items) ->
          Enum.at(work_package.work_items, w11).payload

        w10 == 3 and w11 < length(work_package.work_items) and
          w12 < length(Enum.at(work_package.work_items, w11).extrinsic) and
            Map.has_key?(
              preimages,
              Enum.at(work_package.work_items, w11).extrinsic |> Enum.at(w12)
            ) ->
          Map.get(preimages, Enum.at(work_package.work_items, w11).extrinsic |> Enum.at(w12))

        w10 == 4 and
          w11 < length(Enum.at(work_package.work_items, work_item_index).extrinsic) and
            Map.has_key?(
              preimages,
              Enum.at(work_package.work_items, work_item_index).extrinsic |> Enum.at(w11)
            ) ->
          Map.get(
            preimages,
            Enum.at(work_package.work_items, work_item_index).extrinsic |> Enum.at(w11)
          )

        w10 == 5 and w11 < length(import_segments) and
            w12 < length(Enum.at(import_segments, w11)) ->
          Enum.at(import_segments, w11) |> Enum.at(w12)

        w10 == 6 and w11 < length(Enum.at(import_segments, work_item_index)) ->
          Enum.at(import_segments, work_item_index) |> Enum.at(w11)

        true ->
          nil
      end

    o = registers.r7
    f = min(registers.r8, safe_byte_size(v))
    l = min(registers.r9, safe_byte_size(v) - f)

    write_check = PVM.Memory.check_range_access?(memory, o, l, :write)

    memory_ =
      if v != nil and write_check do
        PVM.Memory.write!(memory, o, binary_part(v, f, l))
      else
        memory
      end

    {exit_reason, w7_} =
      cond do
        !write_check or (w9 == 5 and not PVM.Memory.check_range_access?(memory, w10, 32, :read)) ->
          {:panic, registers.r7}

        v == nil ->
          {:continue, none()}

        true ->
          {:continue, byte_size(v)}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory_,
      context: context
    }
  end

  @spec export_internal(Registers.t(), Memory.t(), Context.t(), non_neg_integer()) :: Internal.t()
  def export_internal(registers, memory, %Context{e: e} = context, export_offset) do
    p = registers.r7
    z = min(registers.r8, Constants.segment_size())

    x =
      case PVM.Memory.read(memory, p, z) do
        {:ok, data} -> Utils.pad_binary_right(data, Constants.segment_size())
        _ -> :error
      end

    {exit_reason, w7_, export_segments_} =
      cond do
        x == :error ->
          {:panic, registers.r7, e}

        length(e) + export_offset >= Constants.max_manifest_size() ->
          {:continue, full(), e}

        true ->
          {:continue, length(e) + export_offset, e ++ [x]}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: %{context | e: export_segments_}
    }
  end

  @spec machine_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def machine_internal(registers, memory, %Context{m: m} = context) do
    [p0, pz, i] = Registers.get(registers, [7, 8, 9])

    p =
      case Memory.read(memory, p0, pz) do
        {:ok, data} -> data
        {:error, _} -> :error
      end

    u = %Memory{} |> Memory.set_default_access(nil)

    # Find first available machine ID
    n =
      if map_size(m) == 0 do
        0
      else
        max_key = Map.keys(m) |> Enum.max()
        # range from 0 to max key + 1
        0..(max_key + 1)
        # remove existing keys
        |> Stream.reject(fn id -> Map.has_key?(m, id) end)
        # take the first one
        |> Stream.take(1)
        # convert to list and get the first element
        |> Enum.at(0)
      end

    {exit_reason, w7_, context_} =
      cond do
        p == :error ->
          {:panic, registers.r7, context}

        true ->
          # Create new machine state M = (p ∈ Y, u ∈ M, i ∈ NR)
          machine = %Integrated{program: p, memory: u, counter: i}
          {:continue, n, %{context | m: Map.put(m, n, machine)}}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: context_
    }
  end

  @spec peek_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def peek_internal(registers, memory, %Context{m: m} = context) do
    [n, o, s, z] = Registers.get(registers, [7, 8, 9, 10])

    {exit_reason, w7_, memory_} =
      cond do
        !PVM.Memory.check_range_access?(memory, o, z, :write) ->
          {:panic, registers.r7, memory}

        !Map.has_key?(m, n) ->
          {:continue, who(), memory}

        !PVM.Memory.check_range_access?(Map.get(m, n).memory, s, z, :read) ->
          {:continue, oob(), memory}

        true ->
          data = Memory.read!(Map.get(m, n).memory, s, z)
          memory_ = Memory.write!(memory, o, data)
          {:continue, ok(), memory_}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory_,
      context: context
    }
  end

  @spec poke_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def poke_internal(registers, memory, %Context{m: m} = context) do
    [n, s, o, z] = Registers.get(registers, [7, 8, 9, 10])

    {exit_reason, w7_, m_} =
      cond do
        !PVM.Memory.check_range_access?(memory, s, z, :read) ->
          {:panic, registers.r7, m}

        !Map.has_key?(m, n) ->
          {:continue, who(), m}

        !PVM.Memory.check_range_access?(Map.get(m, n).memory, o, z, :write) ->
          {:continue, oob(), m}

        true ->
          data = Memory.read!(memory, s, z)
          machine = Map.get(m, n)

          machine_ = %{
            machine
            | memory: Memory.write!(machine.memory, o, data)
          }

          {:continue, ok(), %{m | n => machine_}}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: %{context | m: m_}
    }
  end

  @spec zero_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def zero_internal(registers, %Memory{page_size: zp} = memory, %Context{m: m} = context) do
    [n, p, c] = Registers.get(registers, [7, 8, 9])

    u =
      case Map.has_key?(m, n) do
        true -> Map.get(m, n).memory
        false -> :error
      end

    u_ =
      case u do
        :error ->
          :error

        _ ->
          try do
            Memory.set_access_by_page(u, p, c, :write)
            |> Memory.write!(p * zp, <<0::size(c * zp)>>)
          rescue
            _ -> :error
          end
      end

    {w7_, m_} =
      cond do
        p < 16 or p + c > 0x1_0000 ->
          {huh(), m}

        u == :error ->
          {who(), m}

        true ->
          machine = Map.get(m, n)
          machine_ = %{machine | memory: u_}
          m_ = Map.put(m, n, machine_)
          {ok(), m_}
      end

    %Internal{
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: %{context | m: m_}
    }
  end

  @spec void_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def void_internal(registers, %Memory{page_size: zp} = memory, %Context{m: m} = context) do
    [n, p, c] = Registers.get(registers, [7, 8, 9])

    u =
      case Map.has_key?(m, n) do
        true -> Map.get(m, n).memory
        false -> :error
      end

    u_ =
      case u do
        :error ->
          :error

        _ ->
          try do
            Memory.write!(u, p * zp, <<0::size(c * zp)>>)
            |> Memory.set_access_by_page(p, c, nil)
          rescue
            _ -> :error
          end
      end

    {w7_, m_} =
      cond do
        u == :error ->
          {who(), m}

        p < 16 or p + c > 0x1_0000 or not Memory.check_pages_access?(u, p, c, :read) ->
          {huh(), m}

        true ->
          machine = Map.get(m, n)
          machine_ = %{machine | memory: u_}
          m_ = Map.put(m, n, machine_)
          {ok(), m_}
      end

    %Internal{
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: %{context | m: m_}
    }
  end

  @spec invoke_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def invoke_internal(registers, memory, %Context{m: m} = context) do
    [n, o] = Registers.get(registers, [7, 8])

    {g, w} = read_invoke_params(memory, o)

    {exit_reason, w7_, w8_, memory_, m_} =
      case g do
        :error ->
          {:panic, registers.r7, registers.r8, memory, m}

        gas ->
          case Map.get(m, n) do
            nil ->
              {:continue, who(), registers.r8, memory, m}

            machine ->
              %{program: p, memory: u, counter: i} = machine

              {internal_exit_reason,
               %PVM.State{counter: i_, gas: gas_, registers: w_, memory: u_}} =
                PVM.VM.execute(p, %PVM.State{
                  counter: i,
                  gas: gas,
                  registers: w,
                  memory: u
                })

              write_value =
                <<gas_::64-little>> <>
                  for w <- Registers.get(w_, Enum.to_list(0..12)),
                      into: <<>>,
                      do: <<w::64-little>>

              memory_ = Memory.write!(memory, o, write_value)

              machine_ = %{
                machine
                | memory: u_,
                  counter:
                    case internal_exit_reason do
                      {:ecall, _} -> i_ + 1
                      _ -> i_
                    end
              }

              m_ = Map.put(m, n, machine_)

              case internal_exit_reason do
                {:ecall, host_call_id} ->
                  {:continue, host(), host_call_id, memory_, m_}

                {:fault, fault_address} ->
                  {:continue, fault(), fault_address, memory_, m_}

                :out_of_gas ->
                  {:continue, oog(), registers.r8, memory_, m_}

                :panic ->
                  {:continue, panic(), registers.r8, memory_, m_}

                :halt ->
                  {:continue, halt(), registers.r8, memory_, m_}
              end
          end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, %{r7: w7_, r8: w8_}),
      memory: memory_,
      context: %{context | m: m_}
    }
  end

  @spec read_invoke_params(Memory.t(), non_neg_integer()) ::
          {non_neg_integer(), Registers.t()} | {:error, :error}
  defp read_invoke_params(memory, o) do
    if Memory.check_range_access?(memory, o, 112, :write) do
      <<g::64-little, rest::binary>> = Memory.read!(memory, o, 112)

      values =
        for {chunk, index} <- Enum.with_index(for <<chunk::64-little <- rest>>, do: chunk),
            into: %{},
            do: {index, chunk}

      w = PVM.Registers.set(%PVM.Registers{}, values)
      {g, w}
    else
      {:error, :error}
    end
  end

  @spec expunge_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def expunge_internal(registers, memory, %Context{m: m} = context) do
    n = registers.r7

    {w7_, m_} =
      case Map.get(m, n) do
        nil ->
          {who(), m}

        machine ->
          {machine.counter, Map.delete(m, n)}
      end

    %Internal{
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: %{context | m: m_}
    }
  end
end
