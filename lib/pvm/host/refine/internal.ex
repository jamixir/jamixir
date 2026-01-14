# Formula (B.18) v0.7.2
defmodule PVM.Host.Refine.Internal do
  alias System.State.ServiceAccount
  alias PVM.{Host.Refine.Context, Host.Refine.Result.Internal, Integrated, Registers}
  import PVM.{Constants.HostCallResult, Constants.InnerPVMResult, Host.Util}
  import Pvm.Native

  @page_size PVM.Memory.Constants.page_size()

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  @spec historical_lookup_internal(
          Registers.t(),
          reference(),
          Context.t(),
          non_neg_integer(),
          services(),
          non_neg_integer()
        ) :: Internal.t()
  def historical_lookup_internal(
        registers,
        memory_ref,
        context,
        index,
        service_accounts,
        timeslot
      ) do
    {w7, h, o, w10, w11} = Registers.get_5(registers, 7, 8, 9, 10, 11)

    a =
      cond do
        w7 == 0xFFFF_FFFF_FFFF_FFFF and Map.has_key?(service_accounts, index) ->
          Map.get(service_accounts, index)

        Map.has_key?(service_accounts, w7) ->
          Map.get(service_accounts, w7)

        true ->
          nil
      end

    v =
      case memory_read(memory_ref, h, 32) do
        {:ok, hash} ->
          case a do
            nil -> nil
            _ -> ServiceAccount.historical_lookup(a, timeslot, hash)
          end

        _ ->
          :error
      end

    f = min(w10, safe_byte_size(v))
    l = min(w11, safe_byte_size(v) - f)

    {exit_reason, w7_} =
      cond do
        v == :error ->
          {:panic, w7}

        v == nil ->
          {:continue, none()}

        true ->
          case memory_write(memory_ref, o, binary_part(v, f, l)) do
            {:ok, _} -> {:continue, byte_size(v)}
            _ -> {:panic, w7}
          end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context
    }
  end

  @spec export_internal(Registers.t(), reference(), Context.t(), non_neg_integer()) ::
          Internal.t()
  def export_internal(registers, memory_ref, %Context{e: e} = context, export_offset) do
    {w7, w8} = Registers.get_2(registers, 7, 8)
    p = w7
    z = min(w8, Constants.segment_size())

    x =
      case memory_read(memory_ref, p, z) do
        {:ok, data} -> Utils.pad_binary_right(data, Constants.segment_size())
        _ -> :error
      end

    {exit_reason, w7_, export_segments_} =
      cond do
        x == :error ->
          {:panic, w7, e}

        length(e) + export_offset >= Constants.max_imports() ->
          {:continue, full(), e}

        true ->
          {:continue, length(e) + export_offset, e ++ [x]}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: %{context | e: export_segments_}
    }
  end

  @spec machine_internal(Registers.t(), reference(), Context.t()) :: Internal.t()
  def machine_internal(registers, memory_ref, %Context{m: m} = context) do
    {p0, pz, i} = Registers.get_3(registers, 7, 8, 9)

    p =
      case memory_read(memory_ref, p0, pz) do
        {:ok, data} -> data
        {:error, _} -> :error
      end

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
      if p == :error do
        {:panic, p0, context}
      else
        case PVM.Decoder.deblob(p) do
          {:ok, _} ->
            machine = %Integrated{program: p, memory: build_memory(), counter: i}
            {:continue, n, %{context | m: Map.put(m, n, machine)}}

          {:error, _} ->
            {:continue, huh(), context}
        end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context_
    }
  end

  @spec peek_internal(Registers.t(), reference(), Context.t()) :: Internal.t()
  def peek_internal(registers, memory_ref, %Context{m: m} = context) do
    {n, o, s, z} = Registers.get_4(registers, 7, 8, 9, 10)

    {exit_reason, w7_} =
      case memory_read(memory_ref, o, z) do
        {:error, _} ->
          {:panic, n}

        {:ok, _} ->
          if Map.has_key?(m, n) do
            case memory_read(Map.get(m, n).memory, s, z) do
              {:error, _} ->
                {:continue, oob()}

              {:ok, data} ->
                case memory_write(memory_ref, o, data) do
                  {:ok, _} ->
                    {:continue, ok()}

                  {:error, _} ->
                    {:panic, n}
                end
            end
          else
            {:continue, who()}
          end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context
    }
  end

  @spec poke_internal(Registers.t(), reference(), Context.t()) :: Internal.t()
  def poke_internal(registers, memory_ref, context) do
    {n, s, o, z} = Registers.get_4(registers, 7, 8, 9, 10)

    {exit_reason, w7_} =
      case memory_read(memory_ref, s, z) do
        {:error, _} ->
          {:panic, n}

        {:ok, data} ->
          if Map.has_key?(context.m, n) do
            machine = Map.get(context.m, n)

            case memory_write(machine.memory, o, data) do
              {:ok, _} ->
                {:continue, ok()}

              {:error, _} ->
                {:continue, oob()}
            end
          else
            {:continue, who()}
          end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context
    }
  end

  @spec pages_internal(Registers.t(), reference(), Context.t()) :: Internal.t()
  def pages_internal(registers, _memory_ref, context) do
    {n, p, c, r} = Registers.get_4(registers, 7, 8, 9, 10)

    u =
      case Map.get(context.m, n) do
        nil -> :error
        machine -> machine.memory
      end

    # Early validation checks
    w7_ =
      cond do
        u == :error ->
          who()

        r > 4 or p < 16 or p + c > 0x1_0000 ->
          huh()

        # For r > 2 (modes 3 and 4), check that pages already have read access
        r > 2 and not pages_have_read_access?(u, p, c) ->
          huh()

        true ->
          # Apply the page operation
          start_addr = p * @page_size
          length = c * @page_size

          result =
            cond do
              r < 3 ->
                # Modes 0, 1, 2: zero the memory and set access
                # First set write access to allow zeroing
                set_memory_access(u, start_addr, length, 3)
                # Zero the memory
                zeros = <<0::size(length * 8)>>
                memory_write(u, start_addr, zeros)

                # Then set final access mode
                # 0 = no access, 1 = read only, 3 = read/write
                access_mode =
                  case r do
                    0 -> 0
                    1 -> 1
                    2 -> 3
                  end

                set_memory_access(u, start_addr, length, access_mode)
                :ok

              r == 3 ->
                # Mode 3: just set read access (don't zero)
                set_memory_access(u, start_addr, length, 1)
                :ok

              r == 4 ->
                # Mode 4: just set write access (don't zero)
                set_memory_access(u, start_addr, length, 3)
                :ok
            end

          case result do
            :ok -> ok()
            _ -> huh()
          end
      end

    %Internal{
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: context
    }
  end

  # Check if all pages in range have at least read access by attempting to read
  defp pages_have_read_access?(memory_ref, start_page, page_count) do
    start_addr = start_page * @page_size
    length = page_count * @page_size

    case memory_read(memory_ref, start_addr, length) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @spec invoke_internal(Registers.t(), reference(), Context.t()) :: Internal.t()
  def invoke_internal(registers, memory_ref, %Context{m: m} = context) do
    {w7, w8} = Registers.get_2(registers, 7, 8)
    n = w7
    o = w8
    {g, w} = read_invoke_params(memory_ref, o)

    {exit_reason, w7_, w8_, m_} =
      case g do
        :error ->
          {:panic, w7, w8, m}

        gas ->
          case Map.get(m, n) do
            nil ->
              {:continue, who(), w8, m}

            machine ->
              %{program: p, memory: u, counter: i} = machine

              {internal_exit_reason,
               %PVM.State{counter: i_, gas: gas_, registers: w_, memory: u_}} =
                PVM.VM.execute(p, %PVM.State{counter: i, gas: gas, registers: w, memory: u})

              write_value =
                <<gas_::64-little>> <>
                  for w <- Registers.to_list(w_),
                      into: <<>>,
                      do: <<w::64-little>>

              case memory_write(memory_ref, o, write_value) do
                {:error, _} ->
                  {:panic, w7, w8, m}

                {:ok, _} ->
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
                      {:continue, host(), host_call_id, m_}

                    {:fault, fault_address} ->
                      {:continue, fault(), fault_address, m_}

                    :out_of_gas ->
                      {:continue, oog(), w8, m_}

                    :panic ->
                      {:continue, panic(), w8, m_}

                    :halt ->
                      {:continue, halt(), w8, m_}
                  end
              end
          end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_) |> put_elem(8, w8_)},
      context: %{context | m: m_}
    }
  end

  @spec read_invoke_params(reference(), non_neg_integer()) ::
          {non_neg_integer(), Registers.t()} | {:error, :error}
  defp read_invoke_params(memory_ref, o) do
    case memory_read(memory_ref, o, 112) do
      {:ok, data} ->
        <<g::64-little, rest::binary>> = data

        values =
          for {chunk, index} <- Enum.with_index(for <<chunk::64-little <- rest>>, do: chunk),
              into: %{},
              do: {index, chunk}

        w = PVM.Registers.new(values)
        {g, w}

      {:error, _} ->
        {:error, :error}
    end
  end

  @spec expunge_internal(Registers.t(), reference(), Context.t()) :: Internal.t()
  def expunge_internal(registers, _memory_ref, %Context{m: m} = context) do
    n = registers[7]

    {w7_, m_} =
      case Map.get(m, n) do
        nil ->
          {who(), m}

        machine ->
          {machine.counter, Map.delete(m, n)}
      end

    %Internal{
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      context: %{context | m: m_}
    }
  end
end
