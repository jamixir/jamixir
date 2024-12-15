defmodule PVM.Host.Wrapper do
  defmacro defpure(head, do: body) do
    quote do
      def unquote(head) do
        default_gas = 10
        {gas, registers, memory, context} = {var!(gas), var!(registers), var!(memory), var!(context)}
        if gas < default_gas do
          {:out_of_gas, %{gas: 0, registers: registers, memory: memory}, context}
        else
          {new_registers, new_memory, new_context} = unquote(body)
          {:continue, %{gas: gas - default_gas, registers: new_registers, memory: new_memory}, new_context}
        end
      end
    end
  end
end
