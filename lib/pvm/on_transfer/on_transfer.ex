defmodule PVM.OnTransfer do
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkItem, WorkPackage}
  alias PVM.OnTransfer.Executor
  alias PVM.{Host.General}
  alias PVM.Host.General.FetchArgs
  alias PVM.OnTransfer.OnTransferParams
  alias System.State.ServiceAccount
  alias Util.Hash
  import PVM.Constants.{HostCallResult, HostCallId}
  import PVM.Host.Gas
  import PVM.Types
  import Codec.Encoder
  import Util.Collections, only: [sum_field: 2]

  @spec execute(
          services :: %{integer() => ServiceAccount.t()},
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          transfers :: list(DeferredTransfer.t()),
          extra_args :: %{n0_: Types.hash()}
        ) :: {ServiceAccount.t(), non_neg_integer()}
  def execute(services, timeslot, service_index, transfers, extra_args) do
    do_on_transfer(services, timeslot, service_index, transfers, extra_args)
  end

  def do_on_transfer(services, timeslot, service_index, transfers, %{n0_: n0_}) do
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

      Executor.run(
        code,
        service,
        e({timeslot, service_index, length(transfers)}),
        gas_limit,
        %OnTransferParams{
          service_index: service_index,
          services: services,
          transfers: transfers,
          n0_: n0_
        }
      )
    end
  end

  def handle_host_call(
        n,
        %{gas: gas, registers: registers, memory_ref: memory_ref},
        context,
        %OnTransferParams{
          service_index: service_index,
          services: services,
          transfers: transfers,
          n0_: n0_
        }
      ) do
    host_call_result =
      case host(n) do
        :gas ->
          General.gas(gas, registers, memory_ref, context)

        :fetch ->
          General.fetch(%FetchArgs{
            gas: gas,
            registers: registers,
            memory_ref: memory_ref,
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
          General.lookup(gas, registers, memory_ref, context, service_index, services)

        :read ->
          General.read(gas, registers, memory_ref, context, service_index, services)

        :write ->
          General.write(gas, registers, memory_ref, context, service_index)

        :info ->
          General.info(gas, registers, memory_ref, context, service_index, services)

        :log ->
          General.log(gas, registers, memory_ref, context, nil, service_index)

        _ ->
          %{
            exit_reason: :continue,
            gas: gas - default_gas(),
            registers: %{registers | r: put_elem(registers.r, 7, what())},
            context: context
          }
      end

    %{exit_reason: e, gas: g, registers: r, context: c} = host_call_result

    {e, %{gas: g, registers: r}, c}
  end
end
