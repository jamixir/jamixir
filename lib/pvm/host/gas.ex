defmodule PVM.Host.Gas do

  @default_gas 10
  def default_gas, do: @default_gas

  def check_gas(gas, min_gas \\ default_gas()) do
    {
      if(gas < min_gas, do: :out_of_gas, else: :continue),
      max(0, gas - min_gas)
    }
  end
end
