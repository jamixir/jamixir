defmodule PVM.Host.GasHandler do
  import PVM.Host.Gas

  def with_gas(
        result_module,
        common_args,
        operation_fn,
        extra_args \\ [],
        gas_cost \\ default_gas()
      ) do
    {gas, registers, memory_ref, context} = common_args
    {gas_exit_reason, remaining_gas} = check_gas(gas, gas_cost)

    result =
      struct(result_module, %{
        exit_reason: gas_exit_reason,
        gas: remaining_gas,
        registers: registers,
        context: context
      })

    if gas_exit_reason == :out_of_gas do
      result
    else
      all_args = [registers, memory_ref, context | extra_args]
      operation_result = apply(operation_fn, all_args)
      result_module.new(result, operation_result)
    end
  end
end
