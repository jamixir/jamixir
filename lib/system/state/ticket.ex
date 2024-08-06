defmodule System.State.Ticket do
  @moduledoc """
  represent a ticket, as specified in section 6.2 of the GP.
  equation (51)
  """

  @type t :: %__MODULE__{
          id: <<_::256>>,
          attempt: non_neg_integer(),
  }

  defstruct id: <<>>, attempt: 0


end
