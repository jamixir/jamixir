defmodule Disputes do
  @moduledoc """
  Represents a disputes in the blockchain system, containing a list of verdicts, and optionally, culprits and faults.
  """

  alias __MODULE__.{Verdict, Culprit, Fault}

  @type t :: %__MODULE__{
          verdicts: list(Verdict.t()) | nil,
          culprits: list(Culprit.t()) | nil,
          faults: list(Fault.t()) | nil
        }

  defstruct verdicts: [], culprits: nil, faults: nil

  @doc """
  Initializes a new Dispute struct with the given lists of verdicts, optionally including culprits and faults.
  """
  def new(verdicts, culprits \\ nil, faults \\ nil) do
    %Disputes{
      verdicts: verdicts,
      culprits: culprits,
      faults: faults
    }
  end
end
