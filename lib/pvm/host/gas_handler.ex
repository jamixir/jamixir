defmodule PVM.Host.GasHandler do
  import PVM.Host.Gas

  def with_gas(result_module, common_args, operation_fn, extra_args \\ [], gas_cost \\ default_gas()) do
    {gas, registers, memory, context} = common_args
    {gas_exit_reason, remaining_gas} = check_gas(gas, gas_cost)

    result = struct(result_module, %{
      exit_reason: gas_exit_reason,
      gas: remaining_gas,
      registers: registers,
      memory: memory,
      context: context
    })

    if gas_exit_reason == :out_of_gas do
      result
    else
      operation_result = apply(operation_fn, [registers, memory, context | extra_args])
      result_module.new(result, operation_result)
    end
  end
end
