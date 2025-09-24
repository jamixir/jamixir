defmodule PVM.Host.General.FetchArgs do
  alias PVM.{Registers}
  alias Block.Extrinsic.WorkPackage
  alias System.DeferredTransfer
  alias PVM.Accumulate.Operand

  @type t :: %__MODULE__{
          gas: non_neg_integer(),
          registers: Registers.t(),
          memory_ref: reference(),
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
    :memory_ref,
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
