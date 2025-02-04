defmodule PVM.Accumulate do
  alias System.State.ServiceAccount
  alias PVM.Host.Accumulate.Context
  alias PVM.Host.{Accumulate, General}
  alias System.DeferredTransfer
  alias System.State.Accumulation
  alias PVM.{Accumulate.Operand, ArgInvoc}
  import PVM.Host.Gas

  alias PVM.Accumulate.Utils
  import PVM.Constants.HostCallId

  use Codec.{Encoder, Decoder}

  @doc """
  Formula (B.8) v0.6.0
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
  def execute(accumulation_state, timeslot, service_index, gas, operands, init_fn) do
    # Formula (B.9) v0.6.0
    x = init_fn.(accumulation_state, service_index)
    # Formula (B.10) v0.5.2
    # TODO update B.10 to v0.6.0
    d = Map.merge(x.accumulation.services, x.services)
    s = Context.accumulating_service(x)

    f = fn n, %{gas: gas, registers: registers, memory: memory}, context ->
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

          :quit ->
            Accumulate.quit(gas, registers, memory, context)

          :solicit ->
            Accumulate.solicit(gas, registers, memory, context, timeslot)

          :forget ->
            Accumulate.forget(gas, registers, memory, context, timeslot)

          _ ->
            %Accumulate.Result{
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

    service_code = ServiceAccount.code(accumulation_state.services[service_index])

    if service_code == nil do
      {x.accumulation, [], nil, 0}
    else
      ArgInvoc.execute(
        service_code,
        5,
        gas,
        e({timeslot, service_index, vs(operands)}),
        f,
        {x, x}
      )
      |> Utils.collapse()
    end
  end
end
