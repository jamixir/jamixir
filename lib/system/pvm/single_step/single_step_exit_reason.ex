defmodule System.PVM.SingleStep.ExitReason do
  @type t :: %__MODULE__{
          reason: :halt | :exception | :continue
        }

  defstruct reason: :continue
end
