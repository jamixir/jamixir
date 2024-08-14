defmodule System.State.Ticket do
  @moduledoc """
  represent a ticket, as specified in section 6.2 of the GP.
  Formula (51) v0.3.4
  """

  @type t :: %__MODULE__{
          id: Types.hash(),
          attempt: 0 | 1
        }

  defstruct id: <<>>, attempt: 0

  defimpl Encodable do
    def encode(%System.State.Ticket{}) do
      # TODO
    end
  end
end
