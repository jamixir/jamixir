defmodule PVM.Host.Accumulate.Result.Internal do
  alias PVM.{Registers}
  alias PVM.Host.Accumulate.Context

  @type t() :: %__MODULE__{
          exit_reason: :continue | :out_of_gas | :panic,
          registers: Registers.t(),
          context: {Context.t(), Context.t()}
        }

  defstruct [
    :exit_reason,
    :registers,
    :context
  ]
end

defmodule PVM.Host.Accumulate.Result do
  alias PVM.Host.Accumulate.Context
  alias PVM.Host.Accumulate.Result.Internal
  alias PVM.{Registers}

  @type t() :: %__MODULE__{
          exit_reason: :continue | :out_of_gas | :panic,
          gas: non_neg_integer(),
          registers: Registers.t(),
          context: {Context.t(), Context.t()}
        }

  defstruct [
    :exit_reason,
    :gas,
    :registers,
    :context
  ]

  def new(%__MODULE__{} = self, %Internal{} = internal) do
    %__MODULE__{
      self
      | exit_reason: internal.exit_reason || :continue,
        registers: internal.registers,
        context: internal.context
    }
  end
end
