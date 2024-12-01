defmodule PVM.RefineContext do
  @type t :: %__MODULE__{
          # m
          m: %{non_neg_integer() => PVM.Integrated.t()},
          # e
          e: list(nonempty_binary())
        }

  defstruct [
    # m
    m: %{},
    # e
    e: []
  ]
end
