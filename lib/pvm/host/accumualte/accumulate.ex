defmodule PVM.Host.Accumulate do
  alias PVM.Host.Accumulate.{Context, Result}
  alias System.State.ServiceAccount
  alias PVM.{Memory, Registers}
  import PVM.Host.{Gas, Accumulate.Internal}

  use Codec.Encoder

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  @spec handle_host_call(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()},
          Result.Internal.t() | {:halt | :continue, Result.Internal.t()},
          non_neg_integer()
        ) :: Result.t()
  defp handle_host_call(
         gas,
         registers,
         memory,
         context_pair,
         operation_result,
         gas_cost \\ default_gas()
       ) do
    {exit_reason, remaining_gas} = check_gas(gas, gas_cost)

    result = %Result{
      exit_reason: exit_reason,
      gas: remaining_gas,
      registers: registers,
      memory: memory,
      context: context_pair
    }

    if exit_reason != :continue,
      do: result,
      else: Result.new(result, operation_result)
  end

  @spec bless(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def bless(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      bless_internal(registers, memory, context_pair)
    )
  end

  @spec assign(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def assign(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      assign_internal(registers, memory, context_pair)
    )
  end

  @spec designate(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def designate(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      designate_internal(registers, memory, context_pair)
    )
  end

  @spec checkpoint(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def checkpoint(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      checkpoint_internal(gas, registers, memory, context_pair)
    )
  end

  @spec new(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def new(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      new_internal(registers, memory, context_pair)
    )
  end

  @spec upgrade(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def upgrade(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      upgrade_internal(registers, memory, context_pair)
    )
  end

  @spec transfer(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def transfer(gas, registers, memory, context_pair) do
    gas_cost = 10 + registers.r8 + registers.r9 * 0x1000_0000

    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      transfer_internal(gas, registers, memory, context_pair),
      gas_cost
    )
  end

  @spec quit(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) :: Result.t()
  def quit(gas, registers, memory, context_pair) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      quit_internal(gas, registers, memory, context_pair)
    )
  end

  @spec solicit(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()},
          non_neg_integer()
        ) :: Result.t()
  def solicit(gas, registers, memory, context_pair, timeslot) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      solicit_internal(registers, memory, context_pair, timeslot)
    )
  end

  @spec forget(
          non_neg_integer(),
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()},
          non_neg_integer()
        ) :: Result.t()
  def forget(gas, registers, memory, context_pair, timeslot) do
    handle_host_call(
      gas,
      registers,
      memory,
      context_pair,
      forget_internal(registers, memory, context_pair, timeslot)
    )
  end
end
