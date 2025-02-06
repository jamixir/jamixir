defmodule PVM do
  alias PVM.Host.General
  alias System.DeferredTransfer
  alias System.State.{Accumulation, ServiceAccount}
  alias PVM.{Accumulate.Operand, ArgInvoc, Host, Registers, Host.Accumulate}
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkPackage}
  use Codec.{Encoder, Decoder}
  import PVM.Constants.{HostCallId, HostCallResult}
  import PVM.Host.Gas

  # ΨI : The Is-Authorized pvm invocation function.
  # Formula (B.1) v0.6.0
  @spec authorized(WorkPackage.t(), non_neg_integer(), %{integer() => ServiceAccount.t()}) ::
          binary() | WorkExecutionError.t()
  def authorized(p = %WorkPackage{}, core, services) do
    pc = WorkPackage.authorization_code(p, services)

    {_g, r, nil} =
      ArgInvoc.execute(pc, 0, Constants.gas_is_authorized(), e({p, core}), &authorized_f/3, nil)

    r
  end

  # Formula (B.2) v0.6.0
  @spec authorized_f(non_neg_integer(), PVM.Types.host_call_state(), PVM.Types.context()) ::
          {PVM.Types.exit_reason(), PVM.Types.host_call_state(), PVM.Types.context()}
  def authorized_f(n, %{gas: gas, registers: registers, memory: memory}, _context) do
    if host(n) == :gas do
      %{exit_reason: exit_reason, gas: gas_, registers: registers_, memory: memory} =
        Host.General.gas(gas, registers, memory, nil)

      {exit_reason, %{gas: gas_, registers: registers_, memory: memory}, nil}
    else
      {:continue,
       %{
         gas: gas - default_gas(),
         registers: Registers.set(registers, 7, what()),
         memory: memory
       }, nil}
    end
  end

  # Formula (B.8) v0.6.0
  @spec refine(
          non_neg_integer(),
          WorkPackage.t(),
          binary(),
          list(list(binary())),
          non_neg_integer(),
          %{integer() => ServiceAccount.t()}
        ) ::
          {binary() | WorkExecutionError.t(), list(binary())}
  def refine(
        work_item_index,
        work_package,
        authorizer_output,
        import_segments,
        export_segment_offset,
        services
      ),
      do:
        PVM.Refine.execute(
          work_item_index,
          work_package,
          authorizer_output,
          import_segments,
          export_segment_offset,
          services
        )

  @spec accumulate(
          accumulation_state :: Accumulation.t(),
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          gas :: non_neg_integer(),
          operands :: list(Operand.t()),
          init_fn :: (Accumulation.t(), non_neg_integer() -> Accumulate.Context.t())
        ) :: {
          Accumulation.t(),
          list(DeferredTransfer.t()),
          Types.hash() | nil,
          non_neg_integer()
        }
  def accumulate(accumulation_state, timeslot, service_index, gas, operands, init_fn) do
    PVM.Accumulate.execute(accumulation_state, timeslot, service_index, gas, operands, init_fn)
  end

  # Formula (B.14) v0.6.1
  @spec on_transfer(
          services :: %{integer() => ServiceAccount.t()},
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          transfers :: list(DeferredTransfer.t())
        ) :: ServiceAccount.t()
  def on_transfer(services, timeslot, service_index, transfers) do
    # Formula (B.16) v0.6.0
    f = fn n, %{gas: gas, registers: registers, memory: memory}, context ->
      host_call_result =
        case host(n) do
          :lookup ->
            General.lookup(gas, registers, memory, context, service_index, services)

          :read ->
            General.read(gas, registers, memory, context, service_index, services)

          :write ->
            General.write(gas, registers, memory, context, service_index)

          :gas ->
            General.gas(gas, registers, memory, context)

          :info ->
            General.info(gas, registers, memory, context, service_index, services)

          _ ->
            %{
              exit_reason: :continue,
              gas: gas - default_gas(),
              registers: Registers.set(registers, 7, what()),
              memory: memory,
              context: context
            }
        end

      %{exit_reason: e, gas: g, registers: r, memory: m, context: c} = host_call_result

      {e, %{gas: g, registers: r, memory: m}, c}
    end

    # Formula (B.15) v0.6.0
    service = Map.get(services, service_index)

    service =
      if service != nil do
        update_in(
          service,
          [:balance],
          &for t <- transfers, reduce: &1 do
            acc -> acc + t.amount
          end
        )
      else
        nil
      end

    code = ServiceAccount.code(service)

    if code == nil or length(transfers) == 0 do
      service
    else
      gas_limit = Enum.sum(Enum.map(transfers, & &1.gas_limit))

      # https://github.com/gavofyork/graypaper/pull/170
      {_, _, service_} =
        ArgInvoc.execute(
          code,
          10,
          gas_limit,
          e({timeslot, service_index, vs(transfers)}),
          f,
          service
        )

      service_
    end
  end
end
