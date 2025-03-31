defmodule System.DeferredTransfer do
  # Formula (12.14) v0.6.4 - T

  @type t :: %__MODULE__{
          # s ∈ ℕ_S
          sender: non_neg_integer(),
          # d ∈ ℕ_S
          receiver: non_neg_integer(),
          # a ∈ ℕ_B
          amount: non_neg_integer(),
          # m ∈ 𝕐_W_T
          memo: binary(),
          # g ∈ ℕ_G
          gas_limit: non_neg_integer()
        }

  defstruct sender: 0,
            receiver: 0,
            amount: 0,
            memo: <<0::size(Constants.memo_size() * 8)>>,
            gas_limit: 0

  # Formula (12.26) v0.6.4
  @spec select_transfers_for_destination(list(t()), non_neg_integer()) :: list(t())
  def select_transfers_for_destination(transfers, destination) do
    Enum.with_index(transfers)
    |> Enum.filter(fn {t, _} -> t.receiver == destination end)
    |> Enum.sort_by(fn {t, index} -> {t.sender, index} end)
    |> Enum.map(fn {t, _} -> t end)
  end

  defimpl Encodable do
    use Codec.Encoder
    alias System.DeferredTransfer
    # Formula (C.28) v0.6.4
    def encode(%DeferredTransfer{} = t) do
      <<t.sender::m(service_id), t.receiver::m(service_id), t.amount::m(balance), t.memo::binary,
        t.gas_limit::m(gas)>>
    end
  end
end
