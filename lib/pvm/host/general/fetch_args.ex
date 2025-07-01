defmodule PVM.Host.General.FetchArgs do
  alias PVM.{Registers, Memory}
  alias Block.Extrinsic.WorkPackage
  alias System.DeferredTransfer
  alias PVM.Accumulate.Operand

  @type t :: %__MODULE__{
          gas: non_neg_integer(),
          registers: Registers.t(),
          memory: Memory.t(),
          work_package: WorkPackage.t() | nil,
          n: binary() | nil,
          authorizer_trace: binary() | nil,
          index: non_neg_integer() | nil,
          import_segments: list(list(binary())) | nil,
          preimages: list(list(binary())) | nil,
          operands: list(Operand.t()) | nil,
          transfers: list(DeferredTransfer.t()) | nil,
          context: any()
        }
  defstruct [
    :gas,
    :registers,
    :memory,
    :work_package,
    :n,
    :authorizer_trace,
    :index,
    :import_segments,
    :preimages,
    :operands,
    :transfers,
    :context
  ]
end
