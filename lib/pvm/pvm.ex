defmodule PVM do
  alias System.State.ServiceAccount
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Block.Extrinsic.WorkPackage
  alias PVM.{ArgInvoc, Host, RefineParams, Types, Registers, Host, RefineContext}
  use Codec.Encoder
  import PVM.Constants.{HostCallId, HostCallResult}
  alias PVM.Host.Refine

  @doc """
    Ψ1: The single-step (pvm) machine state-transition function.
    ΨA: The Accumulate pvm invocation function.
    ΨH : The host-function invocation (pvm) with host-function marshalling.
    ΨT : The On-Transfer pvm invocation function.
    Ω: Virtual machine host-call functions.
  """

  # ΨI : The Is-Authorized pvm invocation function.
  # Formula (273) v0.4.5
  @spec authorized(WorkPackage.t(), non_neg_integer(), %{integer() => ServiceAccount.t()}) ::
          binary() | WorkExecutionError.t()
  def authorized(p = %WorkPackage{}, core, services) do
    pc = WorkPackage.authorization_code(p, services)

    {_g, r, nil} =
      ArgInvoc.execute(pc, 0, Constants.gas_is_authorized(), e({p, core}), &authorized_f/3, nil)

    r
  end

  # Formula (274) v0.4.5
  @spec authorized_f(non_neg_integer(), Types.host_call_state(), Types.context()) ::
          {Types.exit_reason(), Types.host_call_state(), Types.context()}
  def authorized_f(n, %{gas: gas, registers: registers, memory: memory}, _context) do
    if host(n) == :gas do
      {exit_reason, gas_, registers_, _} = Host.gas(gas, registers, memory, nil)
      {exit_reason, {gas_, registers_, memory}, nil}
    else
      {:continue,
       %{
         gas: gas - 10,
         registers: Registers.set(registers, 7, what()),
         memory: memory
       }, nil}
    end
  end

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
  @spec refine(RefineParams.t(), %{integer() => ServiceAccount.t()}) ::
          {binary() | WorkExecutionError.t(), list(binary())}
  def refine(%RefineParams{} = params, services) do
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

      {_gas, result, %RefineContext{e: exports}} =
        ArgInvoc.execute(program, 0, params.gas, args, f, %RefineContext{})

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
