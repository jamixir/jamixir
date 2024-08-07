defmodule System.State.BeefyCommitmentMap do
  @moduledoc """
  a set of tuples, each tuple contain a service index and a an accumulation-result tree root
  see section 12.4
  """

  @type t :: %__MODULE__{
          commitments: [{non_neg_integer(), <<_::256>> | nil}]
        }

  defstruct commitments: []
end
