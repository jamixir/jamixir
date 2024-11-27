defmodule PVM do
  alias System.State.ServiceAccount
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Block.Extrinsic.WorkPackage
  alias PVM.{ArgInvoc, Host, Memory, RefineParams, Types}
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
      {exit_reason, gas_, registers_, _} = Host.remaining_gas(gas, registers, memory)
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
  def refine(params = %RefineParams{}, services) do
    if !Map.has_key?(services, params.service), do: {:big, []}
    service = Map.fetch!(services, params.service)
    lookup = ServiceAccount.historical_lookup(service, params.refinement_context.timeslot, params.service_code)
    if lookup == nil, do: {:big, []}
    if byte_size(lookup) > Constants.max_service_code_size(), do: {:big, []}
  end

  # Formula (238) v0.4.5
  @spec skip(non_neg_integer(), bitstring()) :: non_neg_integer()
  def skip(i, k) when is_integer(i) and is_bitstring(k) do
    case k do
      <<_::size(i + 1), rest::bitstring>> -> find_next_one(0, rest, 0)
      # i is beyond bitstring length, implicit 1 found
      _ -> 0
    end
  end

  defp find_next_one(_i, <<>>, count) when count < 24, do: count
  defp find_next_one(_i, <<1::1, _::bitstring>>, count), do: count

  defp find_next_one(i, <<0::1, rest::bitstring>>, count) when count < 24 do
    find_next_one(i + 1, rest, count + 1)
  end

  defp find_next_one(_i, _k, _count), do: 24
end
