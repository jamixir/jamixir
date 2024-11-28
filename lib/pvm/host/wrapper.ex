defmodule PVM.Host.Wrapper do
  @default_gas 10

  def default_gas, do: @default_gas

  @doc """
  Wraps a pure host function with standard gas accounting.
  Pure functions should have signature (registers, memory, context, ...args)
  and return {new_registers, new_memory, new_context}
  """
  def wrap_host_call(gas, registers, memory, context, pure_fn, args) do
    if gas < @default_gas do
      {:out_of_gas, %{
        gas: 0,
        registers: registers,
        memory: memory
      }, context}
    else
      {new_registers, new_memory, new_context} =
        apply(pure_fn, [registers, memory, context | args])

      {:continue, %{
        gas: gas - @default_gas,
        registers: new_registers,
        memory: new_memory
      }, new_context}
    end
  end
end
