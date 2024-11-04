defmodule System.PVM.SingleStep.Result do
  alias System.PVM.Memory
  alias System.PVM.SingleStep.ExitReason

  # Formula (241) v0.4.5
  @type t :: %__MODULE__{
          exit_reason: ExitReason.t(),
          gas_result: Types.gas_result(),
          registers: list(Types.register_value()),
          memory: Memory.t()
        }

  defstruct exit_reason: %ExitReason{},
            gas_result: 0,
            registers: List.duplicate(0, 13),
            memory: %Memory{}
end
