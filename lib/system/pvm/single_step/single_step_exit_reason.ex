defmodule System.PVM.SingleStep.ExitReason do
  @type t :: %__MODULE__{
          reason:
            :halt
            | :exception
            | :continue
            | {:page_fault, Types.register_value()}
            | {:page_fault, Types.register_value()}
            | {:host_call, Types.register_value()}
        }

  defstruct reason: :continue
end
