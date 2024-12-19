defmodule PVM.Refine do
  alias PVM.Registers
  alias System.State.ServiceAccount
  alias Block.Extrinsic.{Guarantee.WorkExecutionError}
  alias PVM.{ArgInvoc, Refine.Params, Host.Refine, Host.General}
  import PVM.Constants.{HostCallResult, HostCallId}
  import PVM.Host.Gas
  import PVM.Types
  use Codec.{Encoder, Decoder}

  @doc """
  ΨR: The Refine pvm invocation function.
  """
  @spec execute(Params.t(), %{integer() => ServiceAccount.t()}) ::
          {binary() | WorkExecutionError.t(), list(binary())}
  def execute(%Params{} = params, services) do
    with {:ok, service} <- fetch_service(services, params.service),
         {:ok, program} <-
           fetch_lookup(service, params.refinement_context.timeslot, params.service_code),
         :ok <- validate_code_size(program) do
      args =
        e(
          {params.service, params.payload, params.work_package_hash, params.refinement_context,
           params.authorizer_hash, params.output, vs(Enum.map(params.extrinsic_data, &vs/1))}
        )

      f = fn n, %{gas: gas, registers: registers, memory: memory}, context ->
        host_call_result =
          case host(n) do
            :historical_lookup ->
            Refine.historical_lookup(
              gas,
              registers,
              memory,
              context,
              params.service,
              services,
              params.refinement_context.timeslot
            )

          :import ->
            Refine.import(gas, registers, memory, context, params.import_segments)

          :export ->
            Refine.export(gas, registers, memory, context, params.export_offset)

          :gas ->
            General.gas(gas, registers, memory, context)

          :machine ->
            Refine.machine(gas, registers, memory, context)

          :peek ->
            Refine.peek(gas, registers, memory, context)

          :zero ->
            Refine.zero(gas, registers, memory, context)

          :poke ->
            Refine.poke(gas, registers, memory, context)

          :void ->
            Refine.void(gas, registers, memory, context)

          :invoke ->
            Refine.invoke(gas, registers, memory, context)

          :expunge ->
            Refine.expunge(gas, registers, memory, context)

          _ ->
            %Refine.Result{
              exit_reason: :continue,
              gas: gas - default_gas(),
              registers: Registers.set(registers, 7, what()),
              memory: memory,
              context: context
            }
        end
        %{
          exit_reason: exit_reason,
          gas: gas,
          registers: registers,
          memory: memory,
          context: context
        } = host_call_result
        {exit_reason, %{gas: gas, registers: registers, memory: memory}, context}

      end

      {_gas, result, %Refine.Context{e: exports}} =
        ArgInvoc.execute(program, 0, params.gas, args, f, %Refine.Context{})

      if result in [:out_of_gas, :panic] do
        {result, []}
      else
        {result, exports}
      end
    else
      {:error, :service_not_found} -> {:bad, []}
      {:error, :invalid_lookup} -> {:bad, []}
      {:error, :code_too_large} -> {:big, []}
    end
  end

  defp fetch_service(services, service_id) do
    if Map.has_key?(services, service_id) do
      {:ok, Map.get(services, service_id)}
    else
      {:error, :service_not_found}
    end
  end

  defp fetch_lookup(service, timeslot, code) do
    case ServiceAccount.historical_lookup(service, timeslot, code) do
      nil -> {:error, :invalid_lookup}
      lookup -> {:ok, lookup}
    end
  end

  defp validate_code_size(lookup) do
    if byte_size(lookup) <= Constants.max_service_code_size() do
      :ok
    else
      {:error, :code_too_large}
    end
  end
end
