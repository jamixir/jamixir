defmodule PVM.Host.General.Result.Internal do
  alias System.State.ServiceAccount
  alias PVM.{Memory, Registers}

  @type t() :: %__MODULE__{
          registers: Registers.t(),
          memory: Memory.t(),
          context: ServiceAccount.t()
        }

  defstruct [
    :registers,
    :memory,
    :context
  ]
end

defmodule PVM.Host.General.Result do
  alias PVM.Host.General.Result.Internal
  alias System.State.ServiceAccount
  alias PVM.{Memory, Registers}

  @type t() :: %__MODULE__{
          exit_reason: :continue | :out_of_gas | :panic,
          gas: non_neg_integer(),
          registers: Registers.t(),
          memory: Memory.t(),
          context: ServiceAccount.t()
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
      | registers: internal.registers,
        memory: internal.memory,
        context: internal.context
    }
  end
end
