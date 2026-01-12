defmodule PVM.Host.Accumulate do
  alias PVM.Host.Gas
  alias PVM.Host.Accumulate.Result
  alias System.State.ServiceAccount
  import PVM.Host.{GasHandler, Accumulate.Internal}
  import PVM.Host.Gas
  import PVM.Constants.HostCallResult
  require Logger

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  def bless(gas, registers, memory_ref, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &bless_internal/3
    )
  end

  def assign(gas, registers, memory_ref, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &assign_internal/3
    )
  end

  def designate(gas, registers, memory_ref, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &designate_internal/3
    )
  end

  def checkpoint(gas, registers, memory_ref, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &checkpoint_internal/4,
      [gas]
    )
  end

  def new(gas, registers, memory_ref, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &new_internal/4,
      [timeslot]
    )
  end

  def upgrade(gas, registers, memory_ref, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &upgrade_internal/3
    )
  end

  def transfer(gas, registers, memory_ref, context_pair) do
    internal_result = transfer_internal(registers, memory_ref, context_pair)

    {gas_exit_reason, remaining_gas} = Gas.check_gas(gas, 10 + internal_result.gas)

    if gas_exit_reason == :out_of_gas do
      %Result{
        exit_reason: gas_exit_reason,
        gas: remaining_gas,
        registers: registers,
        context: context_pair
      }
    else
      %Result{internal_result | gas: remaining_gas}
    end
  end

  def eject(gas, registers, memory_ref, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &eject_internal/4,
      [timeslot]
    )
  end

  def query(gas, registers, memory_ref, context_pair),
    do:
      with_gas(
        Result,
        {gas, registers, memory_ref, context_pair},
        &query_internal/3
      )

  def solicit(gas, registers, memory_ref, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &solicit_internal/4,
      [timeslot]
    )
  end

  def forget(gas, registers, memory_ref, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &forget_internal/4,
      [timeslot]
    )
  end

  def yield(gas, registers, memory_ref, context_pair),
    do:
      with_gas(
        Result,
        {gas, registers, memory_ref, context_pair},
        &yield_internal/3
      )

  def provide(gas, registers, memory_ref, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory_ref, context_pair},
      &provide_internal/3
    )
  end

  def invalid(call, gas, registers, context) do
    Logger.debug("Invalid accumulation host call: #{call}")
    {exit_reason, g_} = check_gas(gas, default_gas())

    %Result{
      exit_reason: exit_reason,
      gas: g_,
      registers: %{registers | r: put_elem(registers.r, 7, what())},
      context: context
    }
  end
end
