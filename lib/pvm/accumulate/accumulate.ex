defmodule PVM.Accumulate do
  alias System.DeferredTransfer
  alias PVM.Accumulate.Operand
  alias System.State.Accumulation
  alias System.State.ServiceAccount
  alias PVM.Accumulate.Executor
  alias System.AccumulationResult
  alias PVM.Host.{Accumulate, Accumulate.Context, General}

  alias PVM.Host.General.FetchArgs
  import PVM.Host.Gas
  alias PVM.Accumulate.Utils
  import PVM.Constants.{HostCallId, HostCallResult}
  require Logger

  @doc """
  Formula (B.9) v0.7.2
  ΨA: The Accumulate pvm invocation function.
  """
  @spec execute(
          accumulation_state :: Accumulation.t(),
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          gas :: non_neg_integer(),
          operands :: list(Operand.t() | DeferredTransfer.t()),
          extra_args :: %{n0_: Types.hash()}
        ) :: AccumulationResult.t()
  def execute(
        accumulation_state,
        timeslot,
        service_index,
        gas,
        operands_or_transfers,
        %{n0_: n0_},
        opts \\ []
      ) do
    # Get trace setting from environment variable
    opts =
      case System.get_env("PVM_TRACE") do
        "true" ->
          Keyword.put(opts, :trace, true)
          |> Keyword.put(:trace_name, System.get_env("TRACE_NAME"))

        _ ->
          opts
      end

    #  s = e except s_d[s]_b = e_d[s]_b + ∑ r_a (r∈x)
    update_path = [:services, service_index, :balance]

    accumulation_state =
      case get_in(accumulation_state, update_path) do
        nil ->
          accumulation_state

        _ ->
          transfers_amount =
            for(%DeferredTransfer{} = d <- operands_or_transfers, do: d.amount) |> Enum.sum()

          update_in(accumulation_state, update_path, &(&1 + transfers_amount))
      end

    # Formula (B.10) v0.7.2
    x = Utils.initializer(n0_, timeslot, accumulation_state, service_index)

    # c = e_d[s]_c
    service_code = ServiceAccount.code(accumulation_state.services[service_index])

    if service_code == nil or byte_size(service_code) > Constants.max_service_code_size() do
      AccumulationResult.new({x.accumulation, [], nil, 0, MapSet.new()})
    else
      encoded_args = Codec.Encoder.e({timeslot, service_index, length(operands_or_transfers)})

      Executor.run(
        service_code,
        x,
        encoded_args,
        gas,
        operands_or_transfers,
        n0_,
        timeslot,
        service_index,
        opts
      )
    end
  end

  # Formula (B.11) v0.7.2
  def handle_host_call(
        host_call_id,
        %{gas: gas, registers: registers, memory_ref: memory_ref},
        {x, _y} = context,
        n0_,
        operands,
        timeslot
      ) do
    d = x.accumulation.services
    s = Context.accumulating_service(x)
    host_call = host(host_call_id)

    host_call_result =
      case host_call do
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
            operands: operands,
            transfers: nil,
            context: context
          })

        :read ->
          General.read(gas, registers, memory_ref, s, x.service, d)
          |> Utils.replace_service(context)

        :write ->
          General.write(gas, registers, memory_ref, s, x.service)
          |> Utils.replace_service(context)

        :lookup ->
          General.lookup(gas, registers, memory_ref, s, x.service, d)
          |> Utils.replace_service(context)

        :info ->
          General.info(gas, registers, memory_ref, s, x.service, d)
          |> Utils.replace_service(context)

        :bless ->
          Accumulate.bless(gas, registers, memory_ref, context)

        :assign ->
          Accumulate.assign(gas, registers, memory_ref, context)

        :designate ->
          Accumulate.designate(gas, registers, memory_ref, context)

        :checkpoint ->
          Accumulate.checkpoint(gas, registers, memory_ref, context)

        :new ->
          Accumulate.new(gas, registers, memory_ref, context, timeslot)

        :upgrade ->
          Accumulate.upgrade(gas, registers, memory_ref, context)

        :transfer ->
          Accumulate.transfer(gas, registers, memory_ref, context)

        :eject ->
          Accumulate.eject(gas, registers, memory_ref, context, timeslot)

        :query ->
          Accumulate.query(gas, registers, memory_ref, context)

        :solicit ->
          Accumulate.solicit(gas, registers, memory_ref, context, timeslot)

        :forget ->
          Accumulate.forget(gas, registers, memory_ref, context, timeslot)

        :yield ->
          Accumulate.yield(gas, registers, memory_ref, context)

        :provide ->
          Accumulate.provide(gas, registers, memory_ref, context)

        :log ->
          General.log(gas, registers, memory_ref, s, nil, x.service)
          |> Utils.replace_service(context)

        _ ->
          g_ = gas - default_gas()

          %General.Result{
            exit_reason: if(g_ < 0, do: :out_of_gas, else: :continue),
            gas: gas - default_gas(),
            registers: %{registers | r: put_elem(registers.r, 7, what())},
            context: context
          }
      end

    %{exit_reason: e, gas: g, registers: r, context: c} = host_call_result

    if e == :panic or e == :out_of_gas do
      Logger.warning("Host call #{host_call} ended with exit reason: #{e}, remaining gas: #{g}")
    end

    {e, %{gas: g, registers: r}, c}
  end
end
