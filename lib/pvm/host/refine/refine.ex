defmodule PVM.Host.Refine do
  alias System.State.ServiceAccount
  alias PVM.{Memory, Registers, Host.Refine.Context}
  alias PVM.Host.Refine.Result
  use Codec.{Decoder, Encoder}
  import PVM.Host.{Refine.Internal}
  import PVM.Host.GasHandler

  @type services() :: %{non_neg_integer() => ServiceAccount.t()}

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
    with_gas(
      Result,
      {gas, registers, memory, context},
      &historical_lookup_internal/6,
      [index, service_accounts, timeslot]
    )
  end

  def export(gas, registers, memory, context, export_offset) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &export_internal/4,
      [export_offset]
    )
  end

  def machine(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &machine_internal/3
    )
  end

  def peek(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &peek_internal/3
    )
  end

  def poke(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &poke_internal/3
    )
  end

  def zero(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &zero_internal/3
    )
  end

  def void(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &void_internal/3
    )
  end

  def invoke(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &invoke_internal/3
    )
  end

  def expunge(gas, registers, memory, context) do
    with_gas(
      Result,
      {gas, registers, memory, context},
      &expunge_internal/3
    )
  end
end
