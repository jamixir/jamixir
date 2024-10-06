defmodule System.PVM.ExitReason do
  @type t :: %__MODULE__{
          # {∎,☇,∞} ∪ { F , h̵} x NR
          reason:
            :halt
            | :exception
            | :out_of_gas
            | {:page_fault, Types.register_value()}
            | {:host_call, Types.register_value()}
        }

  defstruct reason: :halt
end
