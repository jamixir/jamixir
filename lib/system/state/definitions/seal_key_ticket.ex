defmodule System.State.SealKeyTicket do
  # Formula (6.6) v0.7.0 - T
  @type t :: %__MODULE__{
          # y
          id: Types.hash(),
          # e
          attempt: non_neg_integer()
        }

  defstruct id: <<>>, attempt: 0

  defimpl Encodable do
    import Codec.Encoder
    # Formula (C.30) v0.7.0
    def encode(%System.State.SealKeyTicket{} = skt), do: e({skt.id, <<skt.attempt::8>>})
  end

  use Sizes

  def decode(<<id::binary-size(@hash_size), attempt::integer, rest::binary>>) do
    {%__MODULE__{id: id, attempt: attempt}, rest}
  end

  use JsonDecoder
end
