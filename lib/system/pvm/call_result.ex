defmodule System.PVM.CallResult do
  alias System.PVM.ExitReason
  alias System.PVM.Memory

  @type t :: %__MODULE__{
          exit_reason: ExitReason.t(),
          register: Types.register_value(),
          gas_result: Types.gas_result(),
          registers: list(Types.register_value()),
          memory: Memory.t()
        }

  defstruct exit_reason: :halt,
            register: 0,
            gas_result: 0,
            registers: [],
            memory: %Memory{}
end
