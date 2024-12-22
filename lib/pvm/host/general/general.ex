defmodule PVM.Host.General do
  alias PVM.Host.General
  alias System.State.ServiceAccount
  alias PVM.Registers
  import PVM.Host.Gas
  import PVM.Host.General.Internal
  import PVM.Host.GasHandler
  use Codec.Encoder

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  def gas(gas, registers, memory, context, _args \\ []) do
    {exit_reason, remaining_gas} = check_gas(gas)

    result = %General.Result{
      exit_reason: exit_reason,
      gas: remaining_gas,
      registers: registers,
      memory: memory,
      context: context
    }

    if exit_reason == :continue do
      registers_ = Registers.set(registers, :r7, remaining_gas)
      %{result | registers: registers_}
    else
      result
    end
  end

  def lookup(gas, registers, memory, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &lookup_internal/5,
      [service_index, services]
    )
  end

  def read(gas, registers, memory, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &read_internal/5,
      [service_index, services]
    )
  end

  def write(gas, registers, memory, context, service_index) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &write_internal/4,
      [service_index]
    )
  end

  def info(gas, registers, memory, context, service_index, services) do
    with_gas(
      General.Result,
      {gas, registers, memory, context},
      &info_internal/5,
      [service_index, services]
    )
  end
end
