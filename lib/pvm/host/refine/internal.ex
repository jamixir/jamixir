# Formula (B.22) v0.6.0
defmodule PVM.Host.Refine.Internal do
  alias Block.Extrinsic.WorkPackage
  alias System.State.ServiceAccount
  alias PVM.{Host.Refine.Context, Host.Refine.Result.Internal, Integrated, Memory, Registers}
  alias Util.Hash
  use Codec.{Decoder, Encoder}
  import PVM.{Constants.HostCallResult, Constants.InnerPVMResult}
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
      with {:ok, hash} <- PVM.Memory.read(memory, h, 32) do
        case a do
          nil -> nil
          _ -> ServiceAccount.historical_lookup(a, timeslot, hash)
        end
      else
        _ -> :error
      end

    f = min(registers.r10, byte_size(v))
    l = min(registers.r11, byte_size(v) - f)
    is_writable = Memory.check_range_access?(memory, o, l, :write)

    {exit_reason, w7_, memory_} =
      cond do
        v == :error or not is_writable ->
          {:panic, registers.r7, memory}

        v == nil ->
          {:continue, none(), memory}

        true ->
          {:continue, byte_size(v), Memory.write(memory, o, binary_part(v, f, l)) |> elem(1)}
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
          get_in(work_package, [:work_items, w11, :payload])

        w10 == 3 and w11 < length(work_package.work_items) and
          w12 < length(get_in(work_package, [:work_items, w11, :extrinsic])) and
            Map.has_key?(preimages, get_in(work_package, [:work_items, w11, :extrinsic, w12])) ->
          Map.get(preimages, get_in(work_package, [:work_items, w11, :extrinsic, w12]))

        w10 == 4 and
          w11 < length(get_in(work_package, [:work_items, work_item_index, :extrinsic])) and
            Map.has_key?(
              preimages,
              get_in(work_package, [:work_items, work_item_index, :extrinsic, w11])
            ) ->
          Map.get(
            preimages,
            get_in(work_package, [:work_items, work_item_index, :extrinsic, w11])
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
    f = min(registers.r8, byte_size(v))
    l = min(registers.r9, byte_size(v) - f)

    write_check = PVM.Memory.check_range_access?(memory, o, l, :write)

    memory_ =
      if v != nil and write_check do
        PVM.Memory.write(memory, o, binary_part(v, f, l)) |> elem(1)
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

    # Try to read memory segment
    x =
      case PVM.Memory.read(memory, p, z) do
        {:ok, data} -> Utils.pad_binary_right(data, Constants.segment_size())
        _ -> :error
      end

    # Update register 7 and export segments based on conditions
    {registers_, export_segments_} =
      cond do
        # Memory read failed
        x == :error ->
          {Registers.set(registers, :r7, oob()), e}

        # Export segments would exceed max size
        length(e) + export_offset >= Constants.max_manifest_size() ->
          {Registers.set(registers, :r7, full()), e}

        # Success case - append to export segments and update register
        true ->
          {Registers.set(registers, :r7, length(e) + export_offset), e ++ [x]}
      end

    %Internal{registers: registers_, memory: memory, context: %{context | e: export_segments_}}
  end

  @spec machine_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def machine_internal(registers, memory, %Context{m: m} = context) do
    # Extract registers[7..10] for [p0, pz, i]
    [p0, pz, i] = Registers.get(registers, [7, 8, 9])

    p =
      case Memory.read(memory, p0, pz) do
        {:ok, data} -> data
        {:error, _} -> :error
      end

    # Create empty machine state
    u = %Memory{} |> Memory.set_default_access(nil)

    # Find next available machine ID (one below min of existing keys)
    n =
      if map_size(m) == 0 do
        0
      else
        min_id = Map.keys(m) |> Enum.min()
        if min_id > 0, do: min_id - 1, else: nil
      end

    # Update register 7 and memory based on conditions
    {registers_, context_} =
      cond do
        p == :error ->
          # Invalid memory access
          {Registers.set(registers, :r7, oob()), context}

        n == nil ->
          # No available machine IDs
          {Registers.set(registers, :r7, oob()), context}

        true ->
          # Create new machine state M = (p ∈ Y, u ∈ M, i ∈ NR)
          machine = %Integrated{program: p, memory: u, counter: i}
          {Registers.set(registers, :r7, n), %{context | m: Map.put(m, n, machine)}}
      end

    %Internal{registers: registers_, memory: memory, context: context_}
  end

  @spec peek_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def peek_internal(registers, memory, %Context{m: m} = context) do
    # Extract registers[7..11] for [n, o, s, z]
    [n, o, s, z] = Registers.get(registers, [7, 8, 9, 10])

    # Get machine state if n exists in m
    data =
      cond do
        not Map.has_key?(m, n) ->
          nil

        true ->
          %Integrated{memory: u} = Map.get(m, n)
          # Try to read from machine memory
          case {Memory.read(u, s, z), Memory.check_range_access?(memory, o, z, :write)} do
            {{:ok, data}, true} -> data
            _ -> :error
          end
      end

    # Update registers and memory based on conditions
    {registers_, memory_} =
      case data do
        :error ->
          {Registers.set(registers, :r7, oob()), memory}

        nil ->
          {Registers.set(registers, :r7, who()), memory}

        s ->
          {:ok, new_memory} = Memory.write(memory, o, s)
          {Registers.set(registers, :r7, ok()), new_memory}
      end

    %Internal{registers: registers_, memory: memory_, context: context}
  end

  @spec poke_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def poke_internal(registers, memory, %Context{m: m} = context) do
    # Extract registers[7..11] for [n, s, o, z]
    [n, s, o, z] = Registers.get(registers, [7, 8, 9, 10])

    # Get source data if memory access is valid
    s =
      cond do
        not Map.has_key?(m, n) ->
          nil

        true ->
          %Integrated{memory: u} = Map.get(m, n)
          # Check both read from memory and write to machine memory
          case {Memory.read(memory, s, z), Memory.check_range_access?(u, o, z, :write)} do
            # Both read and write permissions OK
            {{:ok, data}, true} -> data
            # Either read or write failed
            _ -> :error
          end
      end

    # Update registers and machine memory based on conditions
    {registers_, context_} =
      case s do
        :error ->
          {Registers.set(registers, :r7, oob()), context}

        nil ->
          {Registers.set(registers, :r7, who()), context}

        s ->
          machine = Map.get(m, n)
          machine_ = %{machine | memory: Memory.write(machine.memory, o, s) |> elem(1)}
          {Registers.set(registers, :r7, ok()), %{context | m: Map.put(m, n, machine_)}}
      end

    %Internal{registers: registers_, memory: memory, context: context_}
  end

  @spec zero_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def zero_internal(registers, %Memory{page_size: zp} = memory, %Context{m: m} = context) do
    [n, p, c] = Registers.get(registers, [7, 8, 9])

    {registers_, context_} =
      cond do
        p < 16 or p + c > 0x1000_00000 / zp ->
          {Registers.set(registers, :r7, oob()), context}

        not Map.has_key?(m, n) ->
          {Registers.set(registers, :r7, who()), context}

        true ->
          machine = Map.get(m, n)

          u_ =
            Memory.set_access_by_page(machine.memory, p, c, :write)
            |> Memory.write(p * zp, <<0::size(c * zp)>>)
            |> elem(1)

          m_ = Map.put(m, n, %{machine | memory: u_})
          {Registers.set(registers, :r7, ok()), %{context | m: m_}}
      end

    %Internal{registers: registers_, memory: memory, context: context_}
  end

  @spec void_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def void_internal(registers, %Memory{page_size: zp} = memory, %Context{m: m} = context) do
    [n, p, c] = Registers.get(registers, [7, 8, 9])

    {registers_, context_} =
      cond do
        p + c >= 0x1_0000_0000 ->
          {Registers.set(registers, :r7, oob()), context}

        not Map.has_key?(m, n) ->
          {Registers.set(registers, :r7, who()), context}

        true ->
          machine = Map.get(m, n)

          case Memory.check_pages_access?(machine.memory, p, c, :read) do
            false ->
              {Registers.set(registers, :r7, oob()), context}

            true ->
              u_ =
                Memory.write(machine.memory, p * zp, <<0::size(c * zp)>>)
                |> elem(1)
                |> Memory.set_access_by_page(p, c, nil)

              {Registers.set(registers, :r7, ok()),
               %{context | m: Map.put(m, n, %{machine | memory: u_})}}
          end
      end

    %Internal{registers: registers_, memory: memory, context: context_}
  end

  @spec invoke_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def invoke_internal(registers, memory, %Context{m: m} = context) do
    # Extract registers and validate initial conditions

    case validate_invoke_params(registers, memory) do
      {:error, _} ->
        %Internal{
          registers: Registers.set(registers, :r7, oob()),
          memory: memory,
          context: context
        }

      {:ok, {n, o, gas_internal, vm_registers}} ->
        {registers_, memory_, context_} =
          case Map.get(m, n) do
            nil ->
              {Registers.set(registers, :r7, who()), memory, context}

            machine ->
              %Integrated{counter: i, memory: u, program: p} = machine

              vm_state = %PVM.State{
                counter: i,
                gas: gas_internal,
                registers: vm_registers,
                memory: u
              }

              # Execute the VM
              {exit_reason, %PVM.State{counter: i_, gas: gas_, registers: w_, memory: u_}} =
                PVM.VM.execute(p, vm_state)

              # gas_ and registers_ go into output memory
              w_list = Registers.get(w_, Enum.to_list(0..12))
              write_value = e_le(gas_, 8) <> (w_list |> Enum.map(&e_le(&1, 4)) |> Enum.join())
              {:ok, memory_} = Memory.write(memory, o, write_value)

              # post execution memory goes into machine (in context)
              machine_ = %{
                machine
                | memory: u_,
                  counter:
                    case exit_reason do
                      {:ecall, _} -> i_ + 1
                      _ -> i_
                    end
              }

              context_ = %{context | m: Map.put(m, n, machine_)}

              {w7_, w8_} =
                case exit_reason do
                  {:ecall, h} -> {host(), h}
                  {:fault, x} -> {fault(), x}
                  :out_of_gas -> {oog(), o}
                  :panic -> {panic(), o}
                  :halt -> {halt(), o}
                  :continue -> {ok(), o}
                end

              {Registers.set(registers, %{r7: w7_, r8: w8_}), memory_, context_}
          end

        %Internal{registers: registers_, memory: memory_, context: context_}
    end
  end

  defp validate_invoke_params(registers, memory) do
    with [n, o] <- Registers.get(registers, [7, 8]),
         # Check if memory range is writable
         true <- Memory.check_range_access?(memory, o, 60, :write),
         # Read gas and register values
         {:ok, <<gas::64-little>>} <- Memory.read(memory, o, 8),
         {:ok, register_bytes} <- Memory.read(memory, o + 8, 13 * 4) do
      # Convert register values to a Registers struct in one pass
      vm_registers =
        register_bytes
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.with_index()
        |> Enum.into(%{}, fn {bytes, index} ->
          {index, de_le(:binary.list_to_bin(bytes), 4)}
        end)
        |> then(&struct(Registers, &1))

      {:ok, {n, o, gas, vm_registers}}
    else
      _ -> {:error, :invalid_params}
    end
  end

  @spec expunge_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def expunge_internal(registers, memory, %Context{m: m} = context) do
    n = registers.r7

    case Map.get(m, n) do
      nil ->
        %Internal{
          registers: Registers.set(registers, :r7, who()),
          memory: memory,
          context: context
        }

      %Integrated{counter: i} ->
        %Internal{
          registers: Registers.set(registers, :r7, i),
          memory: memory,
          context: %{context | m: Map.delete(m, n)}
        }
    end
  end
end
