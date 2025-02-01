# Formula (B.22) v0.6.0
defmodule PVM.Host.Refine.Internal do
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

    [ho, bo, bz] = Registers.get(registers, [8, 9, 10])

    h =
      with {:ok, mem_segment} <- PVM.Memory.read(memory, ho, 32) do
        Hash.default(mem_segment)
      else
        _ -> :error
      end

    v =
      if a != nil and h != :error do
        ServiceAccount.historical_lookup(a, timeslot, h)
      else
        nil
      end

    is_writable = Memory.check_range_access?(memory, bo, bz, :write)

    memory_ =
      if v != nil and is_writable do
        write_value = binary_part(v, 0, min(byte_size(v), bz))
        PVM.Memory.write(memory, bo, write_value) |> elem(1)
      else
        memory
      end

    w7_ =
      cond do
        !is_writable or h == :error -> oob()
        v == nil -> none()
        true -> byte_size(v)
      end

    registers_ = Registers.set(registers, :r7, w7_)
    %Internal{registers: registers_, memory: memory_, context: context}
  end

  @spec import_internal(Registers.t(), Memory.t(), Context.t(), [binary()]) :: Internal.t()
  def import_internal(registers, memory, context, import_segments) do
    w7 = registers.r7
    v = if w7 < length(import_segments), do: Enum.at(import_segments, w7), else: nil
    o = registers.r8
    l = min(registers.r9, Constants.wswe())

    write_check = PVM.Memory.check_range_access?(memory, o, l, :write)

    memory_ =
      if v != nil and write_check do
        PVM.Memory.write(memory, o, v) |> elem(1)
      else
        memory
      end

    # Update register 7 with result
    w7_ =
      cond do
        !write_check -> oob()
        v == nil -> none()
        true -> ok()
      end

    registers_ = Registers.set(registers, :r7, w7_)
    %Internal{registers: registers_, memory: memory_, context: context}
  end

  @spec export_internal(Registers.t(), Memory.t(), Context.t(), non_neg_integer()) :: Internal.t()
  def export_internal(registers, memory, %Context{e: e} = context, export_offset) do
    p = registers.r7
    z = min(registers.r8, Constants.wswe())

    # Try to read memory segment
    x =
      case PVM.Memory.read(memory, p, z) do
        {:ok, data} -> Utils.pad_binary_right(data, Constants.wswe())
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
         {:ok, gas_bytes} <- Memory.read(memory, o, 8),
         {:ok, register_bytes} <- Memory.read(memory, o + 8, 13 * 4) do
      # Decode gas (8 bytes) and registers (13 x 4 bytes)
      gas = de_le(gas_bytes, 8)

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
