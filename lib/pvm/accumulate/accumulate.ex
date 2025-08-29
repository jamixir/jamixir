defmodule PVM.Accumulate do
  alias System.AccumulationResult
  alias PVM.Host.{Accumulate, Accumulate.Context, General}
  alias System.State.{Accumulation, ServiceAccount}
  alias PVM.{Accumulate.Operand, ArgInvoc}
  alias PVM.Host.General.FetchArgs
  import PVM.Host.Gas
  alias PVM.Accumulate.Utils
  import PVM.Constants.{HostCallId, HostCallResult}
  import Codec.Encoder
  require Logger

  @doc """
  Formula (B.9) v0.7.0
  ΨA: The Accumulate pvm invocation function.
  """
  @spec execute(
          accumulation_state :: Accumulation.t(),
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          gas :: non_neg_integer(),
          operands :: list(Operand.t()),
          extra_args :: %{n0_: Types.hash()}
        ) :: AccumulationResult.t()
  def execute(accumulation_state, timeslot, service_index, gas, operands, %{n0_: n0_}, opts \\ []) do
    # Get trace setting from environment variable
    opts =
      case System.get_env("PVM_TRACE") do
        "true" ->
          Keyword.put(opts, :trace, true)
          |> Keyword.put(:trace_name, System.get_env("TRACE_NAME"))

        _ ->
          opts
      end

    # Formula (B.10) v0.7.0
    x = Utils.initializer(n0_, timeslot, accumulation_state, service_index)

    # Formula (B.11) v0.7.0
    f = fn n, %{gas: gas, registers: registers, memory: memory}, {x, _y} = context ->
      d = x.accumulation.services
      s = Context.accumulating_service(x)

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
              operands: operands,
              transfers: nil,
              context: context
            })

          :read ->
            General.read(gas, registers, memory, s, x.service, d)
            |> Utils.replace_service(context)

          :write ->
            General.write(gas, registers, memory, s, x.service) |> Utils.replace_service(context)

          :lookup ->
            General.lookup(gas, registers, memory, s, x.service, d)
            |> Utils.replace_service(context)

          :info ->
            General.info(gas, registers, memory, s, x.service, d)
            |> Utils.replace_service(context)

          :bless ->
            Accumulate.bless(gas, registers, memory, context)

          :assign ->
            Accumulate.assign(gas, registers, memory, context)

          :designate ->
            Accumulate.designate(gas, registers, memory, context)

          :checkpoint ->
            Accumulate.checkpoint(gas, registers, memory, context)

          :new ->
            Accumulate.new(gas, registers, memory, context, timeslot)

          :upgrade ->
            Accumulate.upgrade(gas, registers, memory, context)

          :transfer ->
            Accumulate.transfer(gas, registers, memory, context)

          :eject ->
            Accumulate.eject(gas, registers, memory, context, timeslot)

          :query ->
            Accumulate.query(gas, registers, memory, context)

          :solicit ->
            Accumulate.solicit(gas, registers, memory, context, timeslot)

          :forget ->
            Accumulate.forget(gas, registers, memory, context, timeslot)

          :yield ->
            Accumulate.yield(gas, registers, memory, context)

          :provide ->
            Accumulate.provide(gas, registers, memory, context, service_index)

          :log ->
            General.log(gas, registers, memory, s, nil, x.service)
            |> Utils.replace_service(context)

          _ ->
            %Accumulate.Result{
              exit_reason: :continue,
              gas: gas - default_gas(),
              registers: %{registers | r: put_elem(registers.r, 7, what())},
              memory: memory,
              context: context
            }
        end

      Logger.debug("host call: #{host(n)}, gas: #{host_call_result.gas}")

      %{exit_reason: e, gas: g, registers: r, memory: m, context: c} = host_call_result

      {e, %{gas: g, registers: r, memory: m}, c}
    end

    service_code = ServiceAccount.code(accumulation_state.services[service_index])

    args = e({timeslot, service_index, length(operands)})

    if service_code == nil or byte_size(service_code) > Constants.max_service_code_size() do
      AccumulationResult.new({x.accumulation, [], nil, 0, MapSet.new()})
    else
      ArgInvoc.execute(service_code, 5, gas, args, f, {x, x}, opts)
      |> Utils.collapse()
    end
  end
end
