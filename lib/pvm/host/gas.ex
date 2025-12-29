defmodule PVM.Host.Gas do
  @default_gas 10
  def default_gas, do: @default_gas

  # Formula (B.15) v0.7.2
  # Formula (B.16) v0.7.2
  # Formula (B.17) v0.7.2
  # Formula (B.18) v0.7.2
  # Formula (B.19) v0.7.2
  # Formula (B.20) v0.7.2
  # ϱ ≡ ϱ−g / ∞ if ϱ< g
  def check_gas(gas, min_gas \\ default_gas()) do
    {
      if(gas <= min_gas, do: :out_of_gas, else: :continue),
      max(0, gas - min_gas)
    }
  end
end
