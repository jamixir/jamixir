defmodule PVM.Host.Accumulate do
  alias PVM.Host.Accumulate.Result
  alias System.State.ServiceAccount
  import PVM.Host.{GasHandler, Accumulate.Internal}
  use Codec.Encoder

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

  def bless(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &bless_internal/3
    )
  end

  def assign(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &assign_internal/3
    )
  end

  def designate(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &designate_internal/3
    )
  end

  def checkpoint(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &checkpoint_internal/4,
      [gas]
    )
  end

  def new(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &new_internal/3
    )
  end

  def upgrade(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &upgrade_internal/3
    )
  end

  def transfer(gas, registers, memory, context_pair) do
    gas_cost = 10 + registers.r9

    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &transfer_internal/3,
      [],
      gas_cost
    )
  end

  def eject(gas, registers, memory, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &eject_internal/4,
      [timeslot]
    )
  end

  def query(gas, registers, memory, context_pair),
    do:
      with_gas(
        Result,
        {gas, registers, memory, context_pair},
        &query_internal/3
      )

  def solicit(gas, registers, memory, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &solicit_internal/4,
      [timeslot]
    )
  end

  def forget(gas, registers, memory, context_pair, timeslot) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &forget_internal/4,
      [timeslot]
    )
  end

  def yield(gas, registers, memory, context_pair),
    do:
      with_gas(
        Result,
        {gas, registers, memory, context_pair},
        &yield_internal/3
      )

  def provide(gas, registers, memory, context_pair, service_index) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &provide_internal/4,
      [service_index]
    )
  end
end
