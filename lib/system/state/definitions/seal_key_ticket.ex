defmodule System.State.SealKeyTicket do
  @moduledoc """
  represent a ticket, as specified in section 6.2 of the GP.
  Formula (51) v0.4.1
  """

  @type t :: %__MODULE__{id: Types.hash(), attempt: non_neg_integer()}

  defstruct id: <<>>, attempt: 0

  defimpl Encodable do
    # Formula (310) v0.4.1
    def encode(%System.State.SealKeyTicket{} = e) do
      Codec.Encoder.encode({
        e.id,
        e.attempt
      })
    end
  end

  use JsonDecoder
end
