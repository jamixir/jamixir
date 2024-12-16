defmodule PVM.Host.General do
  alias PVM.Registers
  import PVM.Host.Gas

  def gas(gas, registers, memory, context, _args \\ []) do
    {exit_reason, remaining_gas} = check_gas(gas)
    registers_ = Registers.set(registers, :r7, remaining_gas)

    {exit_reason, %{gas: remaining_gas, registers: registers_, memory: memory}, context}
  end
end
