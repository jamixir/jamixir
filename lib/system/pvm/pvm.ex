defmodule System.PVM do
  alias System.State.ServiceAccount
  alias System.PVM.RefineParams
  alias System.PVM.Host
  alias System.PVM.Constants
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Block.Extrinsic.WorkPackage
  alias System.PVM.Memory
  use Codec.Encoder

  # Formula (33) v0.4.5
  # Ψ: The whole-program pvm machine state-transition function.
  @spec call(System.PVM.CallParams.t()) :: System.PVM.CallResult.t()
  def call(_call_params) do
    # ...
  end

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
    # TODO: get_gas
    gi = 0
    {_g, r, nil} = __MODULE__.marshalling_call(pc, 0, e({p, core}), gi, &authorized_f/4, nil)
    r
  end

  # Formula (274) v0.4.5
  @spec authorized_f(non_neg_integer(), non_neg_integer(), list(non_neg_integer()), Memory.t()) ::
          {integer(), list(non_neg_integer()), Memory.t()}
  def authorized_f(n, gas, registers, memory) do
    # 0 -> gas
    if n == 0 do
      Host.remaining_gas(gas, registers, memory)
    else
      {gas - 10, [Constants.what(), Enum.at(registers, 7) | Enum.drop(registers, 2)], memory}
    end
  end

  # ΨM : The marshalling whole-program pvm machine state-transition function.
  # (Y, N, NG, Y∶ZI, Ω⟨X⟩, X) → (NG, Y ∪ {☇,∞}, X)
  @spec marshalling_call(binary(), non_neg_integer(), binary(), binary(), binary(), binary()) ::
          binary() | WorkExecutionError.t()
  def marshalling_call(_p, _i, _q, _a, _f, _context) do
    # ...
    # TODO
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
  @spec refine(RefineParams.t(), %{integer() => ServiceAccount.t()}) :: {binary() | WorkExecutionError.t(), list(binary())}
  def refine(_params = %RefineParams{}, _services) do
    # TODO
    {<<>>, []}
  end
end
