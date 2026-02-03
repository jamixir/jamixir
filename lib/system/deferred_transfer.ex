defmodule System.DeferredTransfer do
  alias System.DeferredTransfer
  import Codec.Encoder

  # Formula (12.14) v0.7.2 - X
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

  defimpl Encodable do
    import Codec.Encoder
    alias System.DeferredTransfer
    # Formula (C.31) v0.7.2
    def encode(%DeferredTransfer{} = t) do
      # prefix with 1 Formula (C.33)
      <<1::8, t.sender::m(service_id), t.receiver::m(service_id), t.amount::m(balance),
        t.memo::binary, t.gas_limit::m(gas)>>
    end
  end

  @memo_size Constants.memo_size()

  def decode(bin) do
    <<_::8, sender::m(service_id), receiver::m(service_id), amount::m(balance),
      memo::binary-size(@memo_size), gas_limit::m(gas), rest::binary>> = bin

    {%DeferredTransfer{
       sender: sender,
       receiver: receiver,
       amount: amount,
       memo: memo,
       gas_limit: gas_limit
     }, rest}
  end
end
