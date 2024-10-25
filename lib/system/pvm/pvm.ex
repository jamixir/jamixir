defmodule System.PVM do
  alias System.PVM.Host
  alias System.PVM.Constants
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias System.State
  alias Block.Extrinsic.WorkPackage
  alias System.PVM.Memory
  use Codec.Encoder

  # Formula (33) v0.4.1
  # Ψ: The whole-program pvm machine state-transition function.
  @spec call(System.PVM.CallParams.t()) :: System.PVM.CallResult.t()
  def call(_call_params) do
    # ...
  end

  @doc """
    Ψ1: The single-step (pvm) machine state-transition function.
    ΨA: The Accumulate pvm invocation function.
    ΨH : The host-function invocation (pvm) with host-function marshalling.
    ΨI : The Is-Authorized pvm invocation function.
    ΨM : The marshalling whole-program pvm machine state-transition function.
    ΨT : The On-Transfer pvm invocation function.
    Ω: Virtual machine host-call functions.
  """

  # ΨI : The Is-Authorized pvm invocation function.
  # Formula (267) v0.4.1
  @spec authorized(WorkPackage.t(), non_neg_integer(), State.t()) ::
          binary() | WorkExecutionError.t()
  def authorized(p = %WorkPackage{}, core, state = %State{}) do
    pc = WorkPackage.authorization_code(p, state)
    # TODO: get_gas
    gi = 0
    {_g, r, nil} = __MODULE__.marshalling_call(pc, 0, e({p, core}), gi, &authorized_f/4, nil)
    r
  end

  # Formula (268) v0.4.1
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

  # (Y, N, NG, Y∶ZI, Ω⟨X⟩, X) → (NG, Y ∪ {☇,∞}, X)
  @spec marshalling_call(binary(), non_neg_integer(), binary(), binary(), binary(), binary()) ::
          binary() | WorkExecutionError.t()
  def marshalling_call(_p, _i, _q, _a, _f, _context) do
    # ...
    # TODO
  end
end
