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
          authorizer_output: binary() | nil,
          index: non_neg_integer() | nil,
          import_segments: list(list(binary())) | nil,
          preimages: list(list(binary())) | nil,
          operands: list(Operand.t()) | nil,
          transfers: list(DeferredTransfer.t()) | nil,
          # fetch in (0.6.6) does not use the context, so for now i am leaving the type unspecifed
          context: any()
        }
  defstruct [
    :gas,
    :registers,
    :memory,
    :work_package,
    :n,
    :authorizer_output,
    :index,
    :import_segments,
    :preimages,
    :operands,
    :transfers,
    :context
  ]
end
