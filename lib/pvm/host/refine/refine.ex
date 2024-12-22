defmodule PVM.Host.Refine do
  alias System.State.ServiceAccount
  alias PVM.{Memory, Registers, Host.Refine.Context}
  alias PVM.Host.Refine.Result
  use Codec.{Decoder, Encoder}
  import PVM.{Host.Gas, Host.Refine.Internal}
  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  @spec handle_host_call(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          Context.t(),
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

    if exit_reason != :continue do
      result
    else
      Result.new(result, operation_result)
    end
  end

  @spec historical_lookup(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          Context.t(),
          non_neg_integer(),
          services(),
          non_neg_integer()
        ) :: Result.t()
  def historical_lookup(gas, registers, memory, context, index, service_accounts, timeslot) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      historical_lookup_internal(registers, memory, context, index, service_accounts, timeslot)
    )
  end

  def import(gas, registers, memory, context, import_segments) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      import_internal(registers, memory, context, import_segments)
    )
  end

  def export(gas, registers, memory, context, export_offset) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      export_internal(registers, memory, context, export_offset)
    )
  end

  def machine(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      machine_internal(registers, memory, context)
    )
  end

  def peek(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      peek_internal(registers, memory, context)
    )
  end

  def poke(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      poke_internal(registers, memory, context)
    )
  end

  def zero(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      zero_internal(registers, memory, context)
    )
  end

  def void(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      void_internal(registers, memory, context)
    )
  end

  def invoke(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      invoke_internal(registers, memory, context)
    )
  end

  def expunge(gas, registers, memory, context) do
    handle_host_call(
      gas,
      registers,
      memory,
      context,
      expunge_internal(registers, memory, context)
    )
  end
end
