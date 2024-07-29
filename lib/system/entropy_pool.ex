defmodule EntropyPool do
  @moduledoc """
  Represents the state of the entropy pool in the system.
  section 6.4 - Sealing and Entropy Accumulation
  """

  @type t :: %__MODULE__{
          current: binary(),
          history: list(binary())
        }

  defstruct current: "", history: []
end
