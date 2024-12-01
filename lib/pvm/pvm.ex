defmodule PVM do
  alias System.State.ServiceAccount
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Block.Extrinsic.WorkPackage
  alias PVM.{ArgInvoc, Host, RefineParams, Types}
  use Codec.Encoder
  import PVM.Constants.{HostCallId, HostCallResult}

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
    if n == gas() do
      {exit_reason, gas_, registers_, _} = Host.gas(gas, registers, memory, nil)
      {exit_reason, {gas_, registers_, memory}, nil}
    else
      {:continue,
       %{
         gas: gas - 10,
         registers: Enum.take(registers, 7) ++ [what() | Enum.drop(registers, 8)],
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
  def refine(
        %RefineParams{
          service_code: c,
          gas: g,
          service: s,
          work_package_hash: p,
          payload: y,
          refinement_context: rc,
          authorizer_hash: a,
          output: o,
          import_segments: _i,
          extrinsic_data: x,
          export_offset: _eo
        },
        services
      ) do
    if !Map.has_key?(services, s), do: {:bad, []}
    service = Map.fetch!(services, s)

    lookup =
      ServiceAccount.historical_lookup(
        service,
        rc.timeslot,
        c
      )

    if lookup == nil, do: {:bad, []}
    if byte_size(lookup) > Constants.max_service_code_size(), do: {:big, []}
    a = e({s, y, p, rc, a, o, vs(Enum.map(x, &vs/1))})
    {_gas, result, {_m, e}} = ArgInvoc.execute(lookup, 0, g, a, nil, {nil, []})

    if result in [:out_of_gas, :panic] do
      {result, []}
    end

    {result, e}
  end
end
