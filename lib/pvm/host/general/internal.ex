# Formula (B.18) v0.6.0

defmodule PVM.Host.General.Internal do
  import PVM.{Constants.HostCallResult}
  alias PVM.Host.General.Result
  alias PVM.{Memory, Registers}
  alias System.State.ServiceAccount
  alias Util.Hash
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
        do: get_in(a, [:preimage_storage_p, h]),
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
        Hash.default(<<service_index::32-little>> <> mem_segment)
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

    k = read_storage_key(memory, ko, kz, service_index)
    l = current_value_length(k, service_account)
    value_result = Memory.read(memory, vo, vz)

    updated_account =
      case {k, value_result, vo} do
        {k, {:ok, _}, 0} when k != :error ->
          put_in(service_account, [:storage], Map.drop(Map.get(service_account, :storage), [k]))

        {k, {:ok, value}, _} when k != :error ->
          put_in(service_account, [:storage, k], value)

        _ ->
          service_account
      end

    cond do
      ServiceAccount.threshold_balance(updated_account) > updated_account.balance ->
        %Result.Internal{
          registers: Registers.set(registers, :r7, full()),
          memory: memory,
          context: service_account
        }

      k != :error and match?({:ok, _}, value_result) ->
        %Result.Internal{
          registers: Registers.set(registers, :r7, l),
          memory: memory,
          context: updated_account
        }

      true ->
        %Result.Internal{
          registers: Registers.set(registers, :r7, oob()),
          memory: memory,
          context: service_account
        }
    end
  end

  defp read_storage_key(memory, ko, kz, service_index) do
    with {:ok, mem_segment} <- Memory.read(memory, ko, kz) do
      Hash.default(<<service_index::32-little>> <> mem_segment)
    else
      _ -> :error
    end
  end

  defp current_value_length(:error, _service_account), do: none()

  defp current_value_length(k, service_account) do
    if k in Map.keys(service_account.storage),
      do: byte_size(get_in(service_account, [:storage, k])),
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
