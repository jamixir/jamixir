defmodule PVM do
  alias PVM.Registers
  alias System.AccumulationResult
  alias PVM.Host.General
  alias System.DeferredTransfer
  alias System.State.{Accumulation, ServiceAccount}
  alias PVM.{Accumulate.Operand, ArgInvoc, Host}
  alias PVM.Host.General.FetchArgs
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkPackage}
  import Codec.Encoder
  import PVM.Constants.{HostCallId, HostCallResult}
  import PVM.Host.Gas
  import Util.Collections, only: [sum_field: 2]

  # ΨI : The Is-Authorized pvm invocation function.
  # Formula (B.1) v0.7.0
  @callback do_authorized(WorkPackage.t(), non_neg_integer(), %{integer() => ServiceAccount.t()}) ::
              binary() | WorkExecutionError.t()

  @callback do_on_transfer(
              %{integer() => ServiceAccount.t()},
              non_neg_integer(),
              non_neg_integer(),
              list(DeferredTransfer.t()),
              %{n0_: Types.hash()}
            ) :: {ServiceAccount.t(), non_neg_integer()}

  def authorized(p, core, services) do
    module = Application.get_env(:jamixir, :pvm, __MODULE__)
    module.do_authorized(p, core, services)
  end

  def do_authorized(%WorkPackage{} = p, core_index, services) do
    # Formula (B.2) v0.7.0
    f = fn n, %{gas: gas, registers: registers, memory: memory}, _context ->
      host_call_result =
        case host(n) do
          :gas ->
            Host.General.gas(gas, registers, memory, nil)

          :fetch ->
            Host.General.fetch(%FetchArgs{
              gas: gas,
              registers: registers,
              memory: memory,
              work_package: p,
              n: nil,
              authorizer_trace: nil,
              index: nil,
              import_segments: nil,
              preimages: nil,
              operands: nil,
              transfers: nil,
              context: nil
            })

          :log ->
            Host.General.log(gas, registers, memory, nil)

          _ ->
            Registers.put_elem(registers.r, 7, what())

            %General.Result{
              exit_reason: :continue,
              gas: gas - default_gas(),
              registers: registers,
              memory: memory
            }
        end

      %{exit_reason: e, gas: g, registers: r, memory: m, context: _c} = host_call_result

      {e, %{gas: g, registers: r, memory: m}, nil}
    end

    p_u = WorkPackage.authorization_code(p, services)

    w_a = Constants.max_is_authorized_code_size()

    case p_u do
      nil ->
        {:bad, 0}

      bytes when byte_size(bytes) > w_a ->
        {:big, 0}

      _ ->
        args = e(t(core_index))

        {used_gas, result, nil} =
          ArgInvoc.execute(p_u, 0, Constants.gas_is_authorized(), args, f, nil)

        {result, used_gas}
    end
  end

  # Formula (B.5) v0.7.0
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
          extra_args :: %{n0_: Types.hash()}
        ) :: AccumulationResult.t()
  def accumulate(accumulation_state, timeslot, service_index, gas, operands, %{n0_: n0_}) do
    PVM.Accumulate.execute(accumulation_state, timeslot, service_index, gas, operands, %{n0_: n0_})
  end

  # Formula (B.15) v0.7.0
  @spec on_transfer(
          services :: %{integer() => ServiceAccount.t()},
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          transfers :: list(DeferredTransfer.t()),
          extra_args :: %{n0_: Types.hash()}
        ) :: {ServiceAccount.t(), non_neg_integer()}
  def on_transfer(services, timeslot, service_index, transfers, extra_args) do
    module = Application.get_env(:jamixir, :pvm, __MODULE__)
    module.do_on_transfer(services, timeslot, service_index, transfers, extra_args)
  end

  def do_on_transfer(services, timeslot, service_index, transfers, %{n0_: n0_}) do
    # Formula (B.16) v0.7.0
    f = fn n, %{gas: gas, registers: registers, memory: memory}, context ->
      host_call_result =
        case host(n) do
          :gas ->
            General.gas(gas, registers, memory, context)

          :fetch ->
            General.fetch(%FetchArgs{
              gas: gas,
              registers: registers,
              memory: memory,
              work_package: nil,
              n: n0_,
              authorizer_trace: nil,
              index: nil,
              import_segments: nil,
              preimages: nil,
              operands: nil,
              transfers: transfers,
              context: context
            })

          :lookup ->
            General.lookup(gas, registers, memory, context, service_index, services)

          :read ->
            General.read(gas, registers, memory, context, service_index, services)

          :write ->
            General.write(gas, registers, memory, context, service_index)

          :info ->
            General.info(gas, registers, memory, context, service_index, services)

          :log ->
            General.log(gas, registers, memory, context, nil, service_index)

          _ ->
            Registers.put_elem(registers.r, 7, what())

            %{
              exit_reason: :continue,
              gas: gas - default_gas(),
              registers: registers,
              memory: memory,
              context: context
            }
        end

      %{exit_reason: e, gas: g, registers: r, memory: m, context: c} = host_call_result

      {e, %{gas: g, registers: r, memory: m}, c}
    end

    # Formula (B.15) v0.7.0
    service = Map.get(services, service_index)

    service =
      if service != nil do
        update_in(
          service,
          [:balance],
          fn balance -> balance + sum_field(transfers, :amount) end
        )
      else
        nil
      end

    code = ServiceAccount.code(service)

    if code == nil or byte_size(code) > Constants.max_service_code_size() or
         Enum.empty?(transfers) do
      {service, 0}
    else
      gas_limit = sum_field(transfers, :gas_limit)

      {used_gas, _, service_} =
        ArgInvoc.execute(
          code,
          10,
          gas_limit,
          e({timeslot, service_index, length(transfers)}),
          f,
          service
        )

      {service_, used_gas}
    end
  end
end
