defmodule PVM do
  alias System.State.ServiceAccount
  alias PVM.{ArgInvoc, Host, Registers}
  alias Block.Extrinsic.{Guarantee.WorkExecutionError, WorkPackage}
  use Codec.{Encoder, Decoder}
  import PVM.Constants.{HostCallId, HostCallResult}
  import PVM.Host.Gas

  # ΨI : The Is-Authorized pvm invocation function.
  # Formula (B.1) v0.5.2
  @spec authorized(WorkPackage.t(), non_neg_integer(), %{integer() => ServiceAccount.t()}) ::
          binary() | WorkExecutionError.t()
  def authorized(p = %WorkPackage{}, core, services) do
    pc = WorkPackage.authorization_code(p, services)

    {_g, r, nil} =
      ArgInvoc.execute(pc, 0, Constants.gas_is_authorized(), e({p, core}), &authorized_f/3, nil)

    r
  end

  # Formula (B.2) v0.5.2
  @spec authorized_f(non_neg_integer(), PVM.Types.host_call_state(), PVM.Types.context()) ::
          {PVM.Types.exit_reason(), PVM.Types.host_call_state(), PVM.Types.context()}
  def authorized_f(n, %{gas: gas, registers: registers, memory: memory}, _context) do
    if host(n) == :gas do
      %{exit_reason: exit_reason, gas: gas_, registers: registers_, memory: memory} =
        Host.General.gas(gas, registers, memory, nil)

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
