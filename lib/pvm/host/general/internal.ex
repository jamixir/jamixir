defmodule PVM.Host.General.Internal do
  alias System.State.ServiceAccount
  alias Util.Hash
  alias PVM.{Memory, Registers}
  alias PVM.Host.General.Result
  import PVM.{Constants.HostCallResult}
  use Codec.Encoder

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}
  @max_64_bit_value 0xFFFF_FFFF_FFFF_FFFF

  @spec lookup_internal(Registers.t(), Memory.t(), ServiceAccount.t(), integer(), services()) ::
          Result.Internal.t()
  def lookup_internal(registers, memory, service_account, service_index, services) do
    a =
      if registers.r7 in [@max_64_bit_value, service_index],
        do: service_account,
        else: services[registers.r7]

    [ho, bo, bz] = Registers.get(registers, [8, 9, 10])

    h =
      with {:ok, mem_segment} <- Memory.read(memory, ho, 32) do
        Hash.default(mem_segment)
      else
        _ -> :error
      end

    v =
      if a != nil and h in Map.keys(Map.get(a, :preimage_storage_p)),
        do: Map.get(a, :preimage_storage_p, h),
        else: nil

    is_writable = Memory.check_range_access?(memory, bo, bz, :write)

    memory_ =
      if v != nil and is_writable do
        write_value = binary_part(v, 0, min(byte_size(v), bz))

        case Memory.write(memory, bo, write_value) do
          {:ok, memory_} -> memory_
          _ -> memory
        end
      else
        memory
      end

    w7_ =
      if h != :error and is_writable do
        cond do
          v == nil -> none()
          true -> byte_size(v)
        end
      else
        oob()
      end

    registers_ = Registers.set(registers, :r7, w7_)
    %Result.Internal{registers: registers_, memory: memory_, context: service_account}
  end

  @spec read_internal(Registers.t(), Memory.t(), ServiceAccount.t(), integer(), %{
          non_neg_integer() => ServiceAccount.t()
        }) ::
          Result.Internal.t()
  def read_internal(registers, memory, service_account, service_index, services) do
    a =
      cond do
        registers.r7 in [@max_64_bit_value, service_index] -> service_account
        Map.has_key?(services, registers.r7) -> services[registers.r7]
        true -> nil
      end

    [ko, kz, bo, bz] = Registers.get(registers, [8, 9, 10, 11])

    k =
      with {:ok, mem_segment} <- Memory.read(memory, ko, kz) do
        Hash.default(e_le(service_index, 4) <> mem_segment)
      else
        _ -> :error
      end

    v =
      if a != nil and k in Map.keys(Map.get(a, :storage)),
        do: get_in(a, [:storage, k]),
        else: nil

    is_writable = Memory.check_range_access?(memory, bo, bz, :write)

    memory_ =
      if v != nil and is_writable do
        write_value = binary_part(v, 0, min(byte_size(v), bz))
        Memory.write(memory, bo, write_value) |> elem(1)
      else
        memory
      end

    w7_ =
      if k != :error and is_writable do
        cond do
          v == nil -> none()
          true -> byte_size(v)
        end
      else
        oob()
      end

    registers_ = Registers.set(registers, :r7, w7_)
    %Result.Internal{registers: registers_, memory: memory_, context: service_account}
  end

  @spec write_internal(
          Registers.t(),
          Memory.t(),
          ServiceAccount.t(),
          non_neg_integer()
        ) ::
          Result.Internal.t()
  def write_internal(registers, memory, service_account, service_index) do
    [ko, kz, vo, vz] = Registers.get(registers, [8, 9, 10, 11])

    k =
      with {:ok, mem_segment} <- Memory.read(memory, ko, kz) do
        Hash.default(e_le(service_index, 4) <> mem_segment)
      else
        _ -> :error
      end

    a =
      case Memory.read(memory, vo, vz) do
        {:ok, value} ->
          if vo == 0 do
            put_in(service_account, [:storage], Map.drop(Map.get(service_account, :storage), k))
          else
            put_in(service_account, [:storage, k], value)
          end

        _ ->
          :error
      end

    l =
      if k in Map.keys(Map.get(service_account, :storage)),
        do: byte_size(get_in(service_account, [:storage, k])),
        else: none()

    at = ServiceAccount.threshold_balance(a)
    ab = Map.get(a, :balance)

    {registers_, context_} =
      cond do
        k != :error and a != :error and at <= ab ->
          {Registers.set(registers, :r7, l), a}

        at > ab ->
          {Registers.set(registers, :r7, full()), service_account}

        true ->
          {Registers.set(registers, :r7, oob()), service_account}
      end

    %Result.Internal{registers: registers_, memory: memory, context: context_}
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

    is_writable = Memory.check_range_access?(memory, o, byte_size(m || ""), :write)

    memory_ =
      if m != nil and is_writable do
        Memory.write(memory, o, m) |> elem(1)
      else
        memory
      end

    w7_ =
      cond do
        m != nil and is_writable -> ok()
        m == nil -> none()
        true -> oob()
      end

    registers_ = Registers.set(registers, :r7, w7_)
    %Result.Internal{registers: registers_, memory: memory_, context: context}
  end
end
