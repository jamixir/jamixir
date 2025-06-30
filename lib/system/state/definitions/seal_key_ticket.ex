defmodule System.State.SealKeyTicket do
  # Formula (6.6) v0.7.0
  @type t :: %__MODULE__{
          # y
          id: Types.hash(),
          # r
          attempt: non_neg_integer()
        }

  defstruct id: <<>>, attempt: 0

  defimpl Encodable do
    import Codec.Encoder
    # Formula (C.27) v0.6.6
    def encode(%System.State.SealKeyTicket{} = skt) do
      e({skt.id, <<skt.attempt::8>>})
    end
  end

  use Sizes

  def decode(<<id::binary-size(@hash_size), attempt::integer, rest::binary>>) do
    {%__MODULE__{id: id, attempt: attempt}, rest}
  end

  use JsonDecoder
end
