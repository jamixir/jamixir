defmodule PVM.HostInternal do
  alias Util.Hash
  import PVM.Constants.HostCallResult
  alias System.State.ServiceAccount
  alias PVM.Memory
  import PVM.Host.Wrapper

  @moduledoc """
  Ω: Virtual machine host-call functions. See appendix B.
  ΩA: Assign-core host-call.
  ΩC: Checkpoint host-call.
  ΩD: Designate-validators host-call.
  ΩE: Empower-service host-call.
  ΩF : Forget-preimage host-call.
  ΩG: Gas-remaining host-call.
  ΩH: Historical-lookup-preimagehost-call.
  ΩK: Kickoff-pvm host-call.
  ΩM : Make-pvm host-call.
  ΩN : New-service host-call.
  ΩO: Poke-pvm host-call.
  ΩP : Peek-pvm host-call.
  ΩQ: Quit-service host-call.
  ΩS: Solicit-preimage host-call.
  ΩT : Transfer host-call.
  ΩU : Upgrade-service host-call.
  ΩX: Expunge-pvmhost-call.
  ΩY : Import segment host-call.
  ΩZ: Export segment host-call.
  """
  alias PVM.Memory

  defp set_r7(registers, value), do: List.replace_at(registers, 7, value)

  # ΩG: Gas-remaining host-call.
  @callback remaining_gas(
              gas :: non_neg_integer(),
              registers :: list(non_neg_integer()),
              args :: term()
            ) :: any()
  def gas_pure(gas, registers, memory, context, _args \\ []) do
    #  place gas-g on registers[7]
    registers = List.replace_at(registers, 7, gas - default_gas())

    {registers, memory, context}
  end

  # ΩL: Lookup-preimage host-call.
  # ΩR: Read-storage host-call.
  # ΩW : Write-storage host-call.
  # ΩI: Information-on-servicehost-call.

  def historical_lookup_pure(registers, memory, context, index, service_accounts, timeslot) do
    w7 = Enum.at(registers, 7)

    # Pure logic that only returns new registers, memory and context
    # No need to handle gas accounting here
    a =
      cond do
        w7 == 0xFFFF_FFFF_FFFF_FFFF and Map.has_key?(service_accounts, index) ->
          service_accounts[index]

        Map.has_key?(service_accounts, w7) ->
          service_accounts[w7]

        true ->
          nil
      end

    # Extract registers[8..11] for [ho, bo, bz]
    [ho, bo, bz] = Enum.slice(registers, 8, 3)

    # Calculate hash if memory segment is valid
    h =
      with {:ok, mem_segment} <- PVM.Memory.read(memory, ho, 32) do
        Hash.default(mem_segment)
      else
        _ -> :error
      end

    # Lookup value using service account's historical lookup
    v =
      if a != nil and h != :error do
        ServiceAccount.historical_lookup(a, timeslot, h)
      else
        nil
      end

    # Update memory if value exists
    is_writable = Memory.check_range_access(memory, bo, bz, :write)

    updated_memory =
      if v != nil and is_writable do
        write_value = binary_part(v, 0, min(byte_size(v), bz))

        case PVM.Memory.write(memory, bo, write_value) do
          {:ok, new_memory} -> new_memory
          _ -> memory
        end
      else
        memory
      end

    # Set register 7 based on conditions
    r7_value =
      cond do
        !is_writable -> oob()
        v == nil -> none()
        true -> ok()
      end

    {set_r7(registers, r7_value), updated_memory, context}
  end

  def import_pure(registers, memory, context, import_segments) do
    w7 = Enum.at(registers, 7)
    v = if w7 < length(import_segments), do: Enum.at(import_segments, w7), else: nil
    o = Enum.at(registers, 8)
    l = min(Enum.at(registers, 9), Constants.wswe())

    write_check = PVM.Memory.check_range_access(memory, o, l, :write)

    updated_memory =
      if v != nil and write_check do
        case PVM.Memory.write(memory, o, v) do
          {:ok, new_memory} -> new_memory
          _ -> memory
        end
      else
        memory
      end

    # Update register 7 with result
    r7_value =
      cond do
        !write_check -> oob()
        v == nil -> none()
        true -> ok()
      end

    {set_r7(registers, r7_value), updated_memory, context}
  end

  def export_pure(registers, memory, {m, export_segments}, export_offset) do
    p = Enum.at(registers, 7)
    # size, capped by WE WS
    z = min(Enum.at(registers, 8), Constants.wswe())

    # Try to read memory segment
    x =
      case PVM.Memory.read(memory, p, z) do
        {:ok, data} -> Utils.pad_binary_right(data, Constants.wswe())
        _ -> :error
      end

    # Update register 7 and export segments based on conditions
    {new_registers, new_export_segments} =
      cond do
        # Memory read failed
        x == :error ->
          {set_r7(registers, oob()), export_segments}

        # Export segments would exceed max size
        length(export_segments) + export_offset >= Constants.max_manifest_size() ->
          {set_r7(registers, full()), export_segments}

        # Success case - append to export segments and update register
        true ->
          {set_r7(registers, length(export_segments) + export_offset), export_segments ++ [x]}
      end

    {new_registers, memory, {m, new_export_segments}}
  end

  def machine_pure(registers, memory, {m, e} = context) do
    # Extract registers[7..10] for [p0, pz, i]
    [p0, pz, i] = Enum.slice(registers, 7, 3)

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
    {new_registers, new_context} =
      cond do
        p == :error ->
          # Invalid memory access
          {set_r7(registers, oob()), context}

        n == nil ->
          # No available machine IDs
          {set_r7(registers, oob()), context}

        true ->
          # Create new machine state M = (p ∈ Y, u ∈ M, i ∈ NR)
          new_m = Map.put(m, n, {p, u, i})
          {set_r7(registers, n), {new_m, e}}
      end

    {new_registers, memory, new_context}
  end

  def peek_pure(registers, memory, {m, _e} = context) do
    # Extract registers[7..11] for [n, o, s, z]
    [n, o, s, z] = Enum.slice(registers, 7, 4)

    # Get machine state if n exists in m
    s =
      cond do
        not Map.has_key?(m, n) ->
          nil

        true ->
          {_p, machine_memory, _i} = m[n]
          # Try to read from machine memory
          case {Memory.read(machine_memory, s, z),
                Memory.check_range_access(machine_memory, o, z, :write)} do
            {{:ok, data}, :ok} -> data
            _ -> :error
          end
      end

    # Update registers and memory based on conditions
    {new_registers, new_memory} =
      case s do
        :error ->
          {set_r7(registers, oob()), memory}

        nil ->
          {set_r7(registers, who()), memory}

        data ->
          {:ok, new_memory} = Memory.write(memory, o, data)
          {set_r7(registers, ok()), new_memory}
      end

    {new_registers, new_memory, context}
  end

  def poke_pure(registers, memory, {m, e} = context) do
    # Extract registers[7..11] for [n, s, o, z]
    [n, s, o, z] = Enum.slice(registers, 7, 4)

    # Get source data if memory access is valid
    s =
      cond do
        not Map.has_key?(m, n) ->
          nil

        true ->
          {_p, machine_memory, _i} = m[n]
          # Check both read from memory and write to machine memory
          case {Memory.read(memory, s, z),
                Memory.check_range_access(machine_memory, o, z, :write)} do
            # Both read and write permissions OK
            {{:ok, data}, :ok} -> data
            # Either read or write failed
            _ -> :error
          end
      end

    # Update registers and machine memory based on conditions
    {new_registers, new_context} =
      case s do
        :error ->
          {set_r7(registers, oob()), context}

        nil ->
          {set_r7(registers, who()), context}

        data ->
          {p, machine_memory, i} = m[n]
          {:ok, new_machine_memory} = Memory.write(machine_memory, o, data)
          new_m = Map.put(m, n, {p, new_machine_memory, i})
          {set_r7(registers, ok()), {new_m, e}}
      end

    {new_registers, memory, new_context}
  end

  def zero_pure(registers, %Memory{page_size: zp} = memory, {m, e} = context) do
    [n, p, c] = Enum.slice(registers, 7, 3)

    cond do
      p < 16 or p + c > 0x1000_00000 / zp ->
        {set_r7(registers, oob()), memory, context}

      not Map.has_key?(m, n) ->
        {set_r7(registers, who()), memory, context}

      true ->
        {prog, u, i} = Map.get(m, n)

        u_ =
          Memory.set_access(u, p * zp, c * zp, :write)
          |> Memory.write(p * zp, <<0::size(c * zp)>>)

        m_ = Map.put(m, n, {prog, u_, i})
        {set_r7(registers, ok()), memory, {m_, e}}
    end
  end

  def void_pure(registers, %Memory{page_size: zp} = memory, {m, e} = context) do
    [n, p, c] = Enum.slice(registers, 7, 3)

    cond do
      # Check if p + c >= 2^32
      p + c >= 0x1_0000_0000 ->
        {set_r7(registers, oob()), memory, context}

      # Check if machine exists
      not Map.has_key?(m, n) ->
        {set_r7(registers, who()), memory, context}

      true ->
        {prog, u, i} = Map.get(m, n)
        readable_pages = Memory.readable_indices(u)

        # Check if ANY page in range p..p+c-1 is NOT readable
        has_unreadable =
          Enum.any?(p..(p + c - 1), fn page ->
            not MapSet.member?(readable_pages, page)
          end)

        if has_unreadable do
          {set_r7(registers, oob()), memory, context}
        else
          # All pages are readable, proceed with voiding
          u_ =
            Memory.write(u, p * zp, <<0::size(c * zp)>>)
            |> Memory.set_access(p * zp, c * zp, nil)

          m_ = Map.put(m, n, {prog, u_, i})
          {set_r7(registers, ok()), memory, {m_, e}}
        end
    end
  end
end
