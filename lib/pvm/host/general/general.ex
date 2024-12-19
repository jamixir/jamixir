defmodule PVM.Host.General do
  alias PVM.Host.General.Result
  alias System.State.ServiceAccount
  alias PVM.{Memory, Registers}
  import PVM.Host.Gas
  import PVM.Host.General.Internal
  use Codec.Encoder

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  def gas(gas, registers, memory, context, _args \\ []) do
    {exit_reason, remaining_gas} = check_gas(gas)

    result = %Result{
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

  @spec handle_host_call(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          ServiceAccount.t(),
          Result.Internal.t()
        ) :: Result.t()
  defp handle_host_call(gas, registers, memory, context, operation_result) do
    {exit_reason, remaining_gas} = check_gas(gas)

    result = %Result{
      exit_reason: exit_reason,
      gas: remaining_gas,
      registers: registers,
      memory: memory,
      context: context
    }

    if exit_reason != :continue,
      do: result,
      else: Result.new(result, operation_result)
  end

  def lookup(gas, registers, memory, context, service_index, services) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      lookup_internal(registers, memory, context, service_index, services)
    )
  end

  def read(gas, registers, memory, context, service_index, services) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      read_internal(registers, memory, context, service_index, services)
    )
  end

  def write(gas, registers, memory, context, service_index) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      write_internal(registers, memory, context, service_index)
    )
  end

  def info(gas, registers, memory, context, service_index, services) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      info_internal(registers, memory, context, service_index, services)
    )
  end
end
