defmodule System.State.ServiceAccount do
  @moduledoc """
  Formula (9.3) v0.6.6
  """
  alias Codec.VariableSize
  alias System.State.ServiceAccount
  alias Util.Hash
  import Codec.Encoder
  use AccessStruct
  import Codec.JsonEncoder

  @type t :: %__MODULE__{
          # s
          storage: %{Types.hash() => binary()},
          # p
          preimage_storage_p: %{Types.hash() => binary()},
          # l
          preimage_storage_l: %{{Types.hash(), non_neg_integer()} => list(non_neg_integer())},
          # c
          code_hash: Types.hash(),
          # b
          balance: Types.balance(),
          # g
          gas_limit_g: non_neg_integer(),
          # m
          gas_limit_m: non_neg_integer()
        }

  defstruct storage: %{},
            preimage_storage_p: %{},
            preimage_storage_l: %{},
            code_hash: Hash.zero(),
            balance: 0,
            gas_limit_g: 0,
            gas_limit_m: 0

  # Formula (9.8) v0.6.6
  # ai ≡ 2⋅∣al∣ + ∣as∣
  def items_in_storage(%__MODULE__{storage: s, preimage_storage_l: l}) do
    2 * length(Map.keys(l)) + length(Map.keys(s))
  end

  # ao ∈ N2^64 ≡ sum(81 + z) + sum(32 + |x|),
  def octets_in_storage(%__MODULE__{storage: s, preimage_storage_l: l}) do
    Enum.sum(for {_h, z} <- Map.keys(l), do: 81 + z) +
      Enum.sum(for v <- Map.values(s), do: 32 + byte_size(v))
  end

  # at ∈ NB ≡ BS + BI⋅ai + BL⋅al
  @spec threshold_balance(System.State.ServiceAccount.t()) :: Types.balance()
  def threshold_balance(%__MODULE__{} = sa) do
    Constants.service_minimum_balance() +
      Constants.additional_minimum_balance_per_item() * items_in_storage(sa) +
      Constants.additional_minimum_balance_per_octet() * octets_in_storage(sa)
  end

  # Formula (9.4) v0.6.6
  def code(account) do
    {_, code} = code_and_metadata(account)
    code
  end

  def metadata(account) do
    {meta, _} = code_and_metadata(account)
    meta
  end

  defp code_and_metadata(nil), do: {nil, nil}

  defp code_and_metadata(%__MODULE__{code_hash: hash, preimage_storage_p: p}) do
    case Map.get(p, hash) do
      nil -> {nil, nil}
      bin -> VariableSize.decode(bin, :binary)
    end
  end

  # Formula (9.5) v0.6.6
  # Formula (9.6) v0.6.6
  def store_preimage(%__MODULE__{} = a, preimage, timeslot) do
    hash = h(preimage)

    p2 = put_in(a.preimage_storage_p[hash], preimage)
    put_in(p2.preimage_storage_l[{hash, byte_size(preimage)}], [timeslot])
  end

  # Formula (9.7) v0.6.6
  @spec historical_lookup(ServiceAccount.t(), integer(), Types.hash()) :: binary() | nil
  def historical_lookup(
        %__MODULE__{preimage_storage_p: ap, preimage_storage_l: al},
        timeslot,
        hash
      ) do
    with value <- ap[hash] do
      if value != nil and in_storage?(al[{hash, byte_size(value)}], timeslot),
        do: value,
        else: nil
    end
  end

  def historical_lookup(nil, _, _), do: nil

  defp in_storage?(nil, _), do: false
  defp in_storage?([], _), do: false
  defp in_storage?([x], t), do: x <= t
  defp in_storage?([x, y], t), do: x <= t and t < y
  defp in_storage?([x, y, z], t), do: (x <= t and t < y) or z <= t

  defimpl Encodable do
    alias System.State.ServiceAccount
    # Formula (D.2) v0.6.6
    # C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
    @spec encode(System.State.ServiceAccount.t()) :: binary()
    def encode(%ServiceAccount{} = s) do
      octets_in_storage = ServiceAccount.octets_in_storage(s)
      items_in_storage = ServiceAccount.items_in_storage(s)

      s.code_hash <>
        t(s.balance) <>
        <<s.gas_limit_g::m(gas)>> <>
        <<s.gas_limit_m::m(gas)>> <>
        <<octets_in_storage::64-little>> <>
        <<items_in_storage::32-little>>
    end
  end

  def decode(
        <<code_hash::b(hash), balance::m(balance), gas_limit_g::m(gas), gas_limit_m::m(gas),
          rest::binary>>
      ) do
    {%__MODULE__{
       code_hash: code_hash,
       balance: balance,
       gas_limit_g: gas_limit_g,
       gas_limit_m: gas_limit_m
     }, rest}
  end

  use JsonDecoder

  def json_mapping do
    %{
      preimage_storage_p: [&extract_preimages_p/1, :preimages],
      preimage_storage_l: [&extract_preimages_l/1, :lookup_meta],
      storage: [&extract_storage/1, :storage],
      gas_limit_g: {:service, :min_item_gas},
      gas_limit_m: {:service, :min_memo_gas},
      balance: {:service, :balance},
      code_hash: [&extract_code_hash/1, :service]
    }
  end

  def extract_code_hash(service), do: JsonDecoder.from_json(service[:code_hash])

  def extract_storage(storage) do
    for %{key: k, value: v} <- storage || [], into: %{} do
      {JsonDecoder.from_json(k), JsonDecoder.from_json(v)}
    end
  end

  def extract_preimages_p(preimages) do
    for d <- preimages || [],
        into: %{},
        do: {JsonDecoder.from_json(d[:hash]), JsonDecoder.from_json(d[:blob])}
  end

  def extract_preimages_l(history) do
    for d <- history || [], into: %{} do
      {{
         JsonDecoder.from_json(d[:key][:hash]),
         d[:key][:length]
       }, d[:value] || []}
    end
  end

  def to_json_mapping do
    custom_map =
      {:_module,
       {:service,
        fn
          service ->
            %{
              balance: service.balance,
              min_item_gas: service.gas_limit_g,
              min_memo_gas: service.gas_limit_m,
              code_hash: service.code_hash
            }
        end}}

    %{
      storage: {:storage, &for({k, v} <- &1, do: %{key: k, value: v})},
      preimage_storage_p: {:preimages, &to_list(&1, :hash, :blob)},
      preimage_storage_l:
        {:lookup_meta,
         &to_list(
           &1,
           {:key, fn key -> to_object(key, :hash, :length) end},
           :value
         )},
      balance: custom_map,
      code_hash: custom_map,
      gas_limit_g: custom_map,
      gas_limit_m: custom_map
    }
  end
end
