defmodule System.State.SealKeyTicket do
  @moduledoc """
  Formula (6.6) v0.6.2
  """

  @type t :: %__MODULE__{id: Types.hash(), attempt: non_neg_integer()}

  defstruct id: <<>>, attempt: 0

  defimpl Encodable do
    use Codec.Encoder
    # Formula (C.27) v0.6.0
    def encode(%System.State.SealKeyTicket{} = skt) do
      e({skt.id, skt.attempt})
    end
  end

  use Sizes

  def decode(<<id::binary-size(@hash_size), attempt::integer, rest::binary>>) do
    {%__MODULE__{id: id, attempt: attempt}, rest}
  end

  use JsonDecoder
end
