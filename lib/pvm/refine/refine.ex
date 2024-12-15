defmodule PVM.Refine do
  alias PVM.Registers
  alias System.State.ServiceAccount
  alias Block.Extrinsic.{Guarantee.WorkExecutionError}
  alias PVM.{ArgInvoc, Refine.Params, Refine.Context, Host, Host.Refine}
  import PVM.Constants.{HostCallResult, HostCallId}
  use Codec.{Encoder, Decoder}

  @doc """
  ΨR: The Refine pvm invocation function.
  Unlike the other invocation functions, the Refine invocation function implicitly draws upon some recent
  service account state item δ. The specific block from which this comes is not important, as long as it is no
  earlier than its work-package’s lookup-anchor block. It explicitly accepts the work payload, y, together
  with the service index which is the subject of refinement s, the prediction of the hash of that service’s
  code c at the time of reporting, the hash of the containing work-package p, the refinement context c,
  the authorizer hash a and its output o, and an export segment offset ς, the import segments and extrinsic
  data blobs as dictated by the work-item, i and x. It results in either some error J or a pair of the
  refinement output blob and the export sequence.
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
            Host.gas(gas, registers, memory, context)

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
            {:continue,
             %{gas: gas - 10, registers: Registers.set(registers, 7, what()), memory: memory},
             nil}
        end
      end

      {_gas, result, %Context{e: exports}} =
        ArgInvoc.execute(program, 0, params.gas, args, f, %Context{})

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
