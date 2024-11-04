defmodule System.State.ServiceAccount do
  @moduledoc """
  Formula (90) v0.4.5
  Represents a service account in the Jam system, analogous to a smart contract in Ethereum.
  Each service account includes a storage component, preimage lookup dictionaries,
  code hash, balance, and gas limits.

  Formally:
  - `s`: Storage dictionary (D⟨H → Y⟩)
  - `p`: Preimage lookup dictionary (D⟨H → Y⟩)
  - `l`: Preimage lookup dictionary with additional index (D⟨(H, NL) → ⟦NT⟧∶3⟩)
  - `c`: Code hash
  - `b`: Balance
  - `g`, `m`: Gas limits
  """
  alias System.State.ServiceAccount
  alias Util.Hash
  use Codec.Encoder

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

  # Formula (95) v0.4.5
  # ai ≡ 2⋅∣al∣ + ∣as∣
  def items_in_storage(%__MODULE__{storage: s, preimage_storage_l: l}) do
    2 * length(Map.keys(l)) + length(Map.keys(s))
  end

  # al ∈ N2^64 ≡ sum(81 + z) + sum(32 + |x|),
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

  # Formula (91) v0.4.5
  def code(%__MODULE__{code_hash: hash, preimage_storage_p: p}) do
    p[hash]
  end

  # Formula (92) v0.4.5
  # Formula (93) v0.4.5
  def store_preimage(%__MODULE__{} = a, preimage, timeslot) do
    hash = h(preimage)

    p2 = put_in(a.preimage_storage_p[hash], preimage)
    put_in(p2.preimage_storage_l[{hash, byte_size(preimage)}], [timeslot])
  end

  # Formula (94) v0.4.5
  @spec historical_lookup(ServiceAccount.t(), integer(), Types.hash()) :: binary()
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
    alias Codec.Encoder
    alias System.State.ServiceAccount
    # Formula (321) v0.4.5
    # C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
    @spec encode(System.State.ServiceAccount.t()) :: binary()
    def encode(%ServiceAccount{} = s) do
      s.code_hash <>
        Encoder.encode_le(s.balance, 8) <>
        Encoder.encode_le(s.gas_limit_g, 8) <>
        Encoder.encode_le(s.gas_limit_m, 8) <>
        Encoder.encode_le(ServiceAccount.octets_in_storage(s), 8) <>
        Encoder.encode_le(ServiceAccount.items_in_storage(s), 4)
    end
  end
end
