# Formula (B.18) v0.6.5

defmodule PVM.Host.General.Internal do
  import PVM.{Constants.HostCallResult}
  alias PVM.Host.General.Result
  alias PVM.{Memory, Registers}
  alias System.State.ServiceAccount
  alias Util.Hash
  use Codec.Encoder
  import PVM.Host.Util

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}
  @max_64_bit_value 0xFFFF_FFFF_FFFF_FFFF

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
end
