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
  # Formula (B.1) v0.6.6
  @callback do_authorized(WorkPackage.t(), non_neg_integer(), %{integer() => ServiceAccount.t()}) ::
              binary() | WorkExecutionError.t()

  def authorized(p, core, services) do
    module = Application.get_env(:jamixir, :pvm, __MODULE__)
    module.do_authorized(p, core, services)
  end

  def do_authorized(%WorkPackage{} = p, core_index, services) do
    pc = WorkPackage.authorization_code(p, services)

    args = e(t(core_index))
    w_a = Constants.max_is_authorized_code_size()

    # Formula (B.2) v0.6.6
    f = fn n, %{gas: gas, registers: registers, memory: memory}, _context ->
      host_call_result =
        case host(n) do
          :gas ->
            Host.General.gas(gas, registers, memory, nil)

          :fetch ->
            Host.General.fetch(
              gas,
              registers,
              memory,
              p,
              p,
              nil,
              nil,
              nil,
              nil,
              nil,
              nil,
              nil
            )

          :log ->
            Host.General.log(gas, registers, memory, nil)

          _ ->
            %General.Result{
              exit_reason: :continue,
              gas: gas - default_gas(),
              registers: Registers.set(registers, 7, what()),
              memory: memory
            }
        end

      %{exit_reason: e, gas: g, registers: r, memory: m, context: _c} = host_call_result

      {e, %{gas: g, registers: r, memory: m}, nil}
    end

    case pc do
      nil ->
        {:bad, 0}

      bytes when byte_size(bytes) > w_a ->
        {:big, 0}

      _ ->
        {used_gas, result, nil} =
          ArgInvoc.execute(pc, 0, Constants.gas_is_authorized(), args, f, nil)

        {result, used_gas}
    end
  end

  # Formula (B.5) v0.6.5
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

  # Formula (B.14) v0.6.5
  @spec on_transfer(
          services :: %{integer() => ServiceAccount.t()},
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          transfers :: list(DeferredTransfer.t())
        ) :: ServiceAccount.t()
  def on_transfer(services, timeslot, service_index, transfers) do
    # Formula (B.16) v0.6.5
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

          :log ->
            General.log(gas, registers, memory, context, nil, service_index)

          _ ->
            %{
              exit_reason: :continue,
              # GP says it should be gas - default_gas()
              # but traces dont do the same
              gas: gas,
              registers: Registers.set(registers, 7, what()),
              memory: memory,
              context: context
            }
        end

      %{exit_reason: e, gas: g, registers: r, memory: m, context: c} = host_call_result

      {e, %{gas: g, registers: r, memory: m}, c}
    end

    # Formula (B.15) v0.6.5
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

    if code == nil or Enum.empty?(transfers) do
      {service, 0}
    else
      gas_limit = Enum.sum(Enum.map(transfers, & &1.gas_limit))

      {gas, _, service_} =
        ArgInvoc.execute(
          code,
          10,
          gas_limit,
          e({timeslot, service_index, vs(transfers)}),
          f,
          service
        )

      {service_, gas}
    end
  end
end
