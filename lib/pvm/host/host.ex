defmodule PVM.Host do
  alias PVM.Registers
  import PVM.Host.Wrapper
  # ΩG: Gas-remaining host-call.
  @callback remaining_gas(
              gas :: non_neg_integer(),
              registers :: Registers.t(),
              args :: term()
            ) :: any()
  defpure gas(gas, registers, memory, context, _args \\ []) do
    #  place gas-g on registers[7]
    registers = List.replace_at(registers, 7, gas - 10)

    {registers, memory, context}
  end

end
