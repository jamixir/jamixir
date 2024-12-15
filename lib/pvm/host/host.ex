defmodule PVM.Host do
  alias PVM.Registers
  import PVM.Host.Wrapper
  # ΩG: Gas-remaining host-call.
  @callback remaining_gas(
              gas :: non_neg_integer(),
              registers :: Registers.t(),
              args :: term()
            ) :: any()
  def gas_pure(gas, registers, memory, context, _args \\ []) do
    {Registers.set(registers, :r7, gas - default_gas()), memory, context}
  end

  def gas(gas, registers, memory, context, args \\ []) do
    wrap_host_call(gas, registers, memory, context, &gas_pure/4, args)
  end
end
