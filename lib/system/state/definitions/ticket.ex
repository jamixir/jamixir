defmodule System.State.Ticket do
  @moduledoc """
  represent a ticket, as specified in section 6.2 of the GP.
  Formula (51) v0.3.4
  """

  @type t :: %__MODULE__{
          id: <<_::256>>,
          attempt: non_neg_integer()
        }

  defstruct id: <<>>, attempt: 0

  defimpl Encodable do
    def encode(%System.State.Ticket{}) do
      # TODO
    end
  end
end
