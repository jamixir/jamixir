defmodule PVM.Host do
  import PVM.Host.Wrapper
  # ΩG: Gas-remaining host-call.
  @callback remaining_gas(
              gas :: non_neg_integer(),
              registers :: list(non_neg_integer()),
              args :: term()
            ) :: any()
  def gas_pure(gas, registers, memory, context, _args \\ []) do
    #  place gas-g on registers[7]
    registers = List.replace_at(registers, 7, gas - default_gas())

    {registers, memory, context}
  end


  def gas(gas, registers, memory, context, args \\ []) do
    wrap_host_call(gas, registers, memory, context, &gas_pure/4, args)
  end
end
