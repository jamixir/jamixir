# Formula (B.22) v0.7.0
defmodule PVM.Host.Refine.Internal do
  alias System.State.ServiceAccount
  alias PVM.{Host.Refine.Context, Host.Refine.Result.Internal, Integrated, Memory, Registers}
  import PVM.{Constants.HostCallResult, Constants.InnerPVMResult, Host.Util}
  import Pvm.Native
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
      try do
        hash = PVM.Memory.read!(memory, h, 32)

        case a do
          nil -> nil
          _ -> ServiceAccount.historical_lookup(a, timeslot, hash)
        end
      rescue
        _ -> :error
      end

    f = min(w10, safe_byte_size(v))
    l = min(w11, safe_byte_size(v) - f)
    is_writable = Memory.check_range_access?(memory, o, l, :write)

    {exit_reason, w7_, memory_} =
      cond do
        v == :error or not is_writable ->
          {:panic, w7, memory}

        v == nil ->
          {:continue, none(), memory}

        true ->
          {:continue, byte_size(v), Memory.write!(memory, o, binary_part(v, f, l))}
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      memory: memory_,
      context: context
    }
  end

  @spec export_internal(Registers.t(), Memory.t(), Context.t(), non_neg_integer()) :: Internal.t()
  def export_internal(registers, memory, %Context{e: e} = context, export_offset) do
    {w7, w8} = Registers.get_2(registers, 7, 8)
    p = w7
    z = min(w8, Constants.segment_size())

    x =
      case PVM.Memory.read(memory, p, z) do
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
      memory: memory,
      context: %{context | e: export_segments_}
    }
  end

  @spec machine_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def machine_internal(registers, memory, %Context{m: m} = context) do
    {p0, pz, i} = Registers.get_3(registers, 7, 8, 9)

    p =
      case memory_read(memory, p0, pz) do
        {:ok, data} -> data
        {:error, _} -> :error
      end

    u = %Memory{}

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
            machine = %Integrated{program: p, memory: u, counter: i}
            {:continue, n, %{context | m: Map.put(m, n, machine)}}

          {:error, _} ->
            {:continue, huh(), context}
        end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      memory: memory,
      context: context_
    }
  end

  @spec peek_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def peek_internal(registers, memory, %Context{m: m} = context) do
    {n, o, s, z} = Registers.get_4(registers, 7, 8, 9, 10)

    {exit_reason, w7_, memory_} =
      cond do
        !PVM.Memory.check_range_access?(memory, o, z, :write) ->
          {:panic, n, memory}

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
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      memory: memory_,
      context: context
    }
  end

  @spec poke_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def poke_internal(registers, memory, %Context{m: m} = context) do
    {n, s, o, z} = Registers.get_4(registers, 7, 8, 9, 10)

    {exit_reason, w7_, m_} =
      cond do
        !PVM.Memory.check_range_access?(memory, s, z, :read) ->
          {:panic, n, m}

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
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      memory: memory,
      context: %{context | m: m_}
    }
  end

  @spec pages_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def pages_internal(registers, %Memory{page_size: zp} = memory, %Context{m: m} = context) do
    {n, p, c, r} = Registers.get_4(registers, 7, 8, 9, 10)

    u =
      Map.get(m, n, :error)
      |> case do
        :error -> :error
        machine -> machine.memory
      end

    # set_access_by_page could fail if the p < 16 or p + c > 0x1_0000
    # the next "cond" block takes care of that
    u_ =
      try do
        cond do
          u == :error ->
            :error

          r < 3 ->
            m =
              Memory.set_access_by_page(u, p, c, :write)
              |> Memory.write!(p * zp, <<0::size(c * zp)>>)

            cond do
              r == 0 -> Memory.set_access_by_page(m, p, c, nil)
              r == 1 -> Memory.set_access_by_page(m, p, c, :read)
              r == 2 -> Memory.set_access_by_page(m, p, c, :write)
            end

          r == 3 ->
            Memory.set_access_by_page(u, p, c, :read)

          r == 4 ->
            Memory.set_access_by_page(u, p, c, :write)

          true ->
            u
        end
      rescue
        _ -> :error
      end

    {w7_, m_} =
      cond do
        u == :error ->
          {who(), m}

        r > 4 or p < 16 or p + c > 0x1_0000 ->
          {huh(), m}

        r > 2 and not Memory.check_pages_access?(u, p, c, :read) ->
          {huh(), m}

        true ->
          machine = Map.get(m, n)
          machine_ = %{machine | memory: u_}
          m_ = Map.put(m, n, machine_)
          {ok(), m_}
      end

    %Internal{
      registers: %{registers | r: put_elem(registers.r, 7, w7_)},
      memory: memory,
      context: %{context | m: m_}
    }
  end

  @spec invoke_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def invoke_internal(registers, memory, %Context{m: m} = context) do
    {w7, w8} = Registers.get_2(registers, 7, 8)
    n = w7
    o = w8
    {g, w} = read_invoke_params(memory, o)

    {exit_reason, w7_, w8_, memory_, m_} =
      case g do
        :error ->
          {:panic, w7, w8, memory, m}

        gas ->
          case Map.get(m, n) do
            nil ->
              {:continue, who(), w8, memory, m}

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
                  for w <- Registers.to_list(w_),
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
                  {:continue, oog(), w8, memory_, m_}

                :panic ->
                  {:continue, panic(), w8, memory_, m_}

                :halt ->
                  {:continue, halt(), w8, memory_, m_}
              end
          end
      end

    %Internal{
      exit_reason: exit_reason,
      registers: %{registers | r: put_elem(registers.r, 7, w7_) |> put_elem(8, w8_)},
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

      w = PVM.Registers.new(values)
      {g, w}
    else
      {:error, :error}
    end
  end

  @spec expunge_internal(Registers.t(), Memory.t(), Context.t()) :: Internal.t()
  def expunge_internal(registers, memory, %Context{m: m} = context) do
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
      memory: memory,
      context: %{context | m: m_}
    }
  end
end
