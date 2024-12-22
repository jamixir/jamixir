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
    # disregard gas cost for now, and use the default gas = 10
    # since this purutcular gas cost is non-sensical and anyway the gas model
    # is not yet complete
    # https://matrix.to/#/!ddsEwXlCWnreEGuqXZ:polkadot.io/$QapeS2oxrt0qA7h79GrDpzMGXqcTyonTXH1S1VG3X0Y?via=polkadot.io&via=matrix.org&via=parity.io
    # https://matrix.to/#/!ddsEwXlCWnreEGuqXZ:polkadot.io/$MTfPZqDA9zO3ybSPc13zrA8vWf2H9wiJt6AmpT3n5Sg?via=polkadot.io&via=matrix.org&via=parity.io

    # gas_cost = 10 + registers.r8 + registers.r9 * 0x1000_0000
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &transfer_internal/4,
      [gas]
    )
  end

  def quit(gas, registers, memory, context_pair) do
    with_gas(
      Result,
      {gas, registers, memory, context_pair},
      &quit_internal/4,
      [gas]
    )
  end

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
end
