defmodule System.State.SealKeyTicket do
  @moduledoc """
  represent a ticket, as specified in section 6.2 of the GP.
  Formula (51) v0.4.1
  """

  @type t :: %__MODULE__{
          id: Types.hash(),
          entry_index: non_neg_integer()
        }

  defstruct id: <<>>, entry_index: 0

  defimpl Encodable do
    # Formula (310) v0.4.1
    def encode(%System.State.SealKeyTicket{} = e) do
      Codec.Encoder.encode({
        e.id,
        e.entry_index
      })
    end
  end

  use JsonDecoder

  def json_mapping, do: %{entry_index: :attempt}
end
