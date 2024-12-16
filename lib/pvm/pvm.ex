defmodule PVM do

  alias System.State.ServiceAccount
  alias PVM.{ArgInvoc, Host, Registers}
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkPackage}
  use Codec.{Encoder, Decoder}
  import PVM.Constants.{HostCallId, HostCallResult}
  import PVM.Host.Gas

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
  @spec authorized_f(non_neg_integer(), PVM.Types.host_call_state(), PVM.Types.context()) ::
          {PVM.Types.exit_reason(), PVM.Types.host_call_state(), PVM.Types.context()}
  def authorized_f(n, %{gas: gas, registers: registers, memory: memory}, _context) do
    if host(n) == :gas do
      {exit_reason, gas_, registers_, _} = Host.General.gas(gas, registers, memory, nil)
      {exit_reason, {gas_, registers_, memory}, nil}
    else
      {:continue,
       %{
         gas: gas - default_gas(),
         registers: Registers.set(registers, 7, what()),
         memory: memory
       }, nil}
    end
  end
end
