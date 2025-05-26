defmodule PVM.Accumulate do
  alias PVM.Registers
  alias System.State.ServiceAccount
  alias PVM.Host.Accumulate.Context
  alias PVM.Host.{Accumulate, General}
  alias System.DeferredTransfer
  alias System.State.Accumulation
  alias PVM.{Accumulate.Operand, ArgInvoc}
  import PVM.Host.Gas

  alias PVM.Accumulate.Utils
  import PVM.Constants.{HostCallId, HostCallResult}

  use Codec.{Encoder, Decoder}

  @doc """
  Formula (B.9) v0.6.5
  ΨA: The Accumulate pvm invocation function.
  """
  @spec execute(
          accumulation_state :: Accumulation.t(),
          timeslot :: non_neg_integer(),
          service_index :: non_neg_integer(),
          gas :: non_neg_integer(),
          operands :: list(Operand.t()),
          init_fn :: (Accumulation.t(), non_neg_integer() -> Context.t())
        ) :: {
          Accumulation.t(),
          list(DeferredTransfer.t()),
          Types.hash() | nil,
          non_neg_integer()
        }
  def execute(accumulation_state, timeslot, service_index, gas, operands, init_fn, opts \\ []) do
    # Get trace setting from environment variable
    opts =
      case System.get_env("PVM_TRACE") do
        "true" ->
          Keyword.put(opts, :trace, true)
          |> Keyword.put(:trace_name, System.get_env("TRACE_NAME"))

        _ ->
          opts
      end

    # Formula (B.10) v0.6.5
    x = init_fn.(accumulation_state, service_index)

    d = x.accumulation.services
    # Formula (B.11) v0.6.5
    f = fn n, %{gas: gas, registers: registers, memory: memory}, {x, _y} = context ->
      s = Context.accumulating_service(x)

      host_call_result =
        case host(n) do
          :read ->
            General.read(gas, registers, memory, s, x.service, d)
            |> Utils.replace_service(context)

          :write ->
            General.write(gas, registers, memory, s, x.service) |> Utils.replace_service(context)

          :lookup ->
            General.lookup(gas, registers, memory, s, x.service, d)
            |> Utils.replace_service(context)

          :gas ->
            General.gas(gas, registers, memory, context)

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
            Accumulate.new(gas, registers, memory, context)

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

          _ ->
            %Accumulate.Result{
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

    service_code = ServiceAccount.code(accumulation_state.services[service_index])

    args = e({timeslot, service_index, vs(operands)})

    if service_code == nil or byte_size(service_code) > Constants.max_service_code_size() do
      {x.accumulation, [], nil, 0, []}
    else
      ArgInvoc.execute(service_code, 5, gas, args, f, {x, x}, opts)
      |> Utils.collapse()
      |> Tuple.append([{service_index, service_code}])
    end
  end
end
