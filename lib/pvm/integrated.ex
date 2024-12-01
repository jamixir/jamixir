defmodule PVM.Integrated do
  alias PVM.Memory

  @type t :: %__MODULE__{
          # p
          program: binary(),
          # u
          memory: Memory.t(),
          # i
          counter: non_neg_integer()
        }

  defstruct [
    # p
    program: <<>>,
    # u
    memory: %Memory{},
    # i
    counter: 0
  ]
end
