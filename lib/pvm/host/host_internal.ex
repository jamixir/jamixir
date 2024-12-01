defmodule PVM.HostInternal do
  alias PVM.Integrated
  alias Util.Hash
  import PVM.Constants.HostCallResult
  alias System.State.ServiceAccount
  alias PVM.{Memory, RefineContext}
  import PVM.Host.Wrapper
  use Codec.Decoder

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

    a =
      cond do
        w7 == 0xFFFF_FFFF_FFFF_FFFF and Map.has_key?(service_accounts, index) ->
          Map.get(service_accounts, index)

        Map.has_key?(service_accounts, w7) ->
          Map.get(service_accounts, w7)

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
        !is_writable or h == :error -> oob()
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

  def export_pure(registers, memory, %RefineContext{e: e} = context, export_offset) do
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
          {set_r7(registers, oob()), e}

        # Export segments would exceed max size
        length(e) + export_offset >= Constants.max_manifest_size() ->
          {set_r7(registers, full()), e}

        # Success case - append to export segments and update register
        true ->
          {set_r7(registers, length(e) + export_offset), e ++ [x]}
      end

    {new_registers, memory, %{context | e: new_export_segments}}
  end

  def machine_pure(registers, memory, %RefineContext{m: m} = context) do
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
          machine = %Integrated{program: p, memory: u, counter: i}
          {set_r7(registers, n), %{context | m: Map.put(m, n, machine)}}
      end

    {new_registers, memory, new_context}
  end

  def peek_pure(registers, memory, %RefineContext{m: m} = context) do
    # Extract registers[7..11] for [n, o, s, z]
    [n, o, s, z] = Enum.slice(registers, 7, 4)

    # Get machine state if n exists in m
    s =
      cond do
        not Map.has_key?(m, n) ->
          nil

        true ->
          %Integrated{memory: u} = Map.get(m, n)
          # Try to read from machine memory
          case {Memory.read(u, s, z), Memory.check_range_access(u, o, z, :write)} do
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

        s ->
          {:ok, new_memory} = Memory.write(memory, o, s)
          {set_r7(registers, ok()), new_memory}
      end

    {new_registers, new_memory, context}
  end

  def poke_pure(registers, memory, %RefineContext{m: m} = context) do
    # Extract registers[7..11] for [n, s, o, z]
    [n, s, o, z] = Enum.slice(registers, 7, 4)

    # Get source data if memory access is valid
    s =
      cond do
        not Map.has_key?(m, n) ->
          nil

        true ->
          %Integrated{memory: u} = Map.get(m, n)
          # Check both read from memory and write to machine memory
          case {Memory.read(u, s, z), Memory.check_range_access(u, o, z, :write)} do
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

        s ->
          machine = Map.get(m, n)
          machine_ = %{machine | memory: Memory.write(machine.memory, o, s) |> elem(1)}
          {set_r7(registers, ok()), %{context | m: Map.put(m, n, machine_)}}
      end

    {new_registers, memory, new_context}
  end

  def zero_pure(registers, %Memory{page_size: zp} = memory, %RefineContext{m: m} = context) do
    [n, p, c] = Enum.slice(registers, 7, 3)

    cond do
      p < 16 or p + c > 0x1000_00000 / zp ->
        {set_r7(registers, oob()), memory, context}

      not Map.has_key?(m, n) ->
        {set_r7(registers, who()), memory, context}

      true ->
        machine = Map.get(m, n)
        u_ =
          Memory.set_access_by_page(machine.memory, p, c, :write)
          |> Memory.write(p * zp, <<0::size(c * zp)>>)
          |> elem(1)
        m_ = Map.put(m, n, %{machine | memory: u_})
        {set_r7(registers, ok()), memory, %{context | m: m_}}
    end
  end

  def void_pure(registers, %Memory{page_size: zp} = memory, %RefineContext{m: m} = context) do
    [n, p, c] = Enum.slice(registers, 7, 3)

    cond do
      p + c >= 0x1_0000_0000 ->
        {set_r7(registers, oob()), memory, context}

      not Map.has_key?(m, n) ->
        {set_r7(registers, who()), memory, context}

      true ->
        machine = Map.get(m, n)
        case Memory.check_pages_access(machine.memory, p, c, :read) do
          {:error, _} ->
            {set_r7(registers, oob()), memory, context}
          :ok ->
            u_ =
              Memory.write(machine.memory, p * zp, <<0::size(c * zp)>>)
              |> elem(1)
              |> Memory.set_access_by_page(p, c, nil)

            {set_r7(registers, ok()), memory,
             %{context | m: Map.put(m, n, %{machine | memory: u_})}}
        end
    end
  end

  def invoke_pure(registers, memory, {m, e} = context) do
    with [o, n] <- Enum.slice(registers, 7, 2),

         # Check if memory range is writable
         :ok <- Memory.check_range_access(memory, o, 60, :write),
         # Read gas and register values
         {:ok, gas_bytes} <- Memory.read(memory, o, 8),
         {:ok, register_bytes} <- Memory.read(memory, o + 8, 13 * 4) do
      # Decode gas (8 bytes) and registers (13 x 4 bytes)
      gas = de_le(gas_bytes, 8)

      registers =
        register_bytes
        |> :binary.bin_to_list()
        |> Enum.chunk_every(4)
        |> Enum.map(&:binary.list_to_bin/1)
        |> Enum.map(&de_le(&1, 4))

      {set_r7(registers, ok()), memory, context}
    else
      _ -> {set_r7(registers, oob()), memory, context}
    end
  end
end
