defmodule System.State.ServiceAccount do
  @moduledoc """
  Formula (90) v0.3.4
  Represents a service account in the Jam system, analogous to a smart contract in Ethereum.
  Each service account includes a storage component, preimage lookup dictionaries,
  code hash, balance, and gas limits.

  Formally:
  - `s`: Storage dictionary (D⟨H → Y⟩)
  - `p`: Preimage lookup dictionary (D⟨H → Y⟩)
  - `l`: Preimage lookup dictionary with additional index (D⟨(H, NL) → ⟦NT ⟧∶3⟩)
  - `c`: Code hash
  - `b`: Balance
  - `g`, `m`: Gas limits
  """
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
          balance: non_neg_integer(),
          # g
          gas_limit_g: non_neg_integer(),
          # m
          gas_limit_m: non_neg_integer()
        }

  defstruct storage: %{},
            preimage_storage_p: %{},
            preimage_storage_l: %{},
            code_hash: <<0::256>>,
            balance: 0,
            gas_limit_g: 0,
            gas_limit_m: 0

  # Formula (95) v0.3.4
  # ai ≡ 2⋅∣al∣ + ∣as∣
  def items_in_storage(%__MODULE__{storage: s, preimage_storage_l: l}) do
    2 * length(Map.keys(l)) + length(Map.keys(s))
  end

  # al ∈ N2^64 ≡ sum(81 + z) + sum(32 + |x|),
  def octets_in_storage(%__MODULE__{storage: s, preimage_storage_l: l}) do
    octets_in_preimage_storage_l =
      Map.keys(l)
      |> Enum.map(fn {_h, z} -> 81 + z end)
      |> Enum.sum()

    # total octets in storage s
    octets_in_storage =
      Map.values(s)
      |> Enum.map(&(32 + length(&1)))
      |> Enum.sum()

    octets_in_preimage_storage_l + octets_in_storage
  end

  defimpl Encodable do
    alias Codec.Encoder
    alias System.State.ServiceAccount
    # Formula (292)
    # C(255, s) ↦ ac ⌢ E8(ab, ag, am, al) ⌢ E4(ai) ,
    def encode(%ServiceAccount{} = s) do
      s.code_hash <> Encoder.encode_le(ServiceAccount.items_in_storage(s), 4)
    end
  end
end
