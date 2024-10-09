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
    # Formula (332) v0.4.1
    def encode(%System.State.SealKeyTicket{} = e) do
      Codec.Encoder.encode({
        e.id,
        e.entry_index
      })
    end
  end

  def from_json(%{"id" => id, "attempt" => entry_index}) do
    %System.State.SealKeyTicket{
      id: id |> Utils.hex_to_binary(),
      entry_index: entry_index
    }
  end
end
