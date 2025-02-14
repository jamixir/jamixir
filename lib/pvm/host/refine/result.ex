defmodule PVM.Host.Refine.Result.Internal do
  alias PVM.{Memory, Registers}
  alias PVM.Host.Refine.Context

  @type t() :: %__MODULE__{
          exit_reason: :continue | :out_of_gas | :panic,
          registers: Registers.t(),
          memory: Memory.t(),
          context: Context.t()
        }

  defstruct [
    exit_reason: :continue,
    registers: %Registers{},
    memory: %Memory{},
    context: %Context{}
  ]
end

defmodule PVM.Host.Refine.Result do
  alias PVM.Host.Refine.Result.Internal
  alias PVM.{Memory, Registers}
  alias PVM.Host.Refine.Context

  @type t() :: %__MODULE__{
          exit_reason: :continue | :out_of_gas | :panic,
          gas: non_neg_integer(),
          registers: Registers.t(),
          memory: Memory.t(),
          context: Context.t()
        }

  defstruct [
    :exit_reason,
    :gas,
    :registers,
    :memory,
    :context
  ]

  def new(%__MODULE__{} = self, %Internal{} = internal) do
    %__MODULE__{
      self
      | exit_reason: internal.exit_reason,
        registers: internal.registers,
        memory: internal.memory,
        context: internal.context
    }
  end
end
