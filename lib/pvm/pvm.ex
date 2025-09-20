defmodule PVM do
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkPackage}
  alias PVM.{Accumulate.Operand, ArgInvoc, Host}
  alias PVM.Host.General
  alias PVM.Host.General.FetchArgs
  alias System.AccumulationResult
  alias System.DeferredTransfer
  alias System.State.{Accumulation, ServiceAccount}
  import Codec.Encoder
  import PVM.Constants.{HostCallId, HostCallResult}
  import PVM.Host.Gas

  # ΨI : The Is-Authorized pvm invocation function.
  # Formula (B.1) v0.7.2
  @callback do_authorized(WorkPackage.t(), non_neg_integer(), %{integer() => ServiceAccount.t()}) ::
              binary() | WorkExecutionError.t()

  @callback do_on_transfer(
              %{integer() => ServiceAccount.t()},
              non_neg_integer(),
              non_neg_integer(),
              list(DeferredTransfer.t()),
              %{n0_: Types.hash()}
            ) :: {ServiceAccount.t(), non_neg_integer()}

  @callback do_refine(
              non_neg_integer(),
              WorkPackage.t(),
              binary(),
              list(list(binary())),
              non_neg_integer(),
              %{integer() => ServiceAccount.t()},
              %{{Types.hash(), non_neg_integer()} => binary()}
            ) ::
              {binary() | WorkExecutionError.t(), list(binary())}

  def authorized(p, core, services) do
    module = Application.get_env(:jamixir, :pvm, __MODULE__)
    module.do_authorized(p, core, services)
  end

  def do_authorized(%WorkPackage{} = p, core_index, services),
    do: PVM.Authorize.execute(p, core_index, services)

  def refine(
        work_item_index,
        work_package,
        authorizer_output,
        import_segments,
        export_segment_offset,
        services,
        preimages
      ) do
    module = Application.get_env(:jamixir, :pvm, __MODULE__)

    module.do_refine(
      work_item_index,
      work_package,
      authorizer_output,
      import_segments,
      export_segment_offset,
      services,
      preimages
    )
  end

  def do_refine(
        work_item_index,
        work_package,
        authorizer_output,
        import_segments,
        export_segment_offset,
        services,
        preimages
      ),
      do:
        PVM.Refine.execute(
          work_item_index,
          work_package,
          authorizer_output,
          import_segments,
          export_segment_offset,
          services,
          preimages
        )

  @spec accumulate(
          accumulation_state :: Accumulation.t(),
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          gas :: non_neg_integer(),
          operands :: list(Operand.t()),
          extra_args :: %{n0_: Types.hash()}
        ) :: AccumulationResult.t()
  def accumulate(accumulation_state, timeslot, service_index, gas, operands, %{n0_: n0_}) do
    PVM.Accumulate.execute(accumulation_state, timeslot, service_index, gas, operands, %{n0_: n0_})
  end
end
