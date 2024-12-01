defmodule PVM.Host.Refine do
  import PVM.Host.Wrapper
  import PVM.Host.Refine.Internal

  @moduledoc """
  Ω: Virtual machine host-call functions. See appendix B.
  ΩA: Assign-core host-call.
  ΩC: Checkpoint host-call.
  ΩD: Designate-validators host-call.
  ΩE: Empower-service host-call.
  ΩF : Forget-preimage host-call.
  ΩG: Gas-remaining host-call.
  ΩH: Historical-lookup-preimagehost-call.
  ΩK: Kickoff-pvm host-call.
  ΩM : Make-pvm host-call.
  ΩN : New-service host-call.
  ΩO: Poke-pvm host-call.
  ΩP : Peek-pvm host-call.
  ΩQ: Quit-service host-call.
  ΩS: Solicit-preimage host-call.
  ΩT : Transfer host-call.
  ΩU : Upgrade-service host-call.
  ΩX: Expunge-pvmhost-call.
  ΩY : Import segment host-call.
  ΩZ: Export segment host-call.
  """

  def historical_lookup(gas, registers, memory, context, index, service_accounts, timeslot) do
    wrap_host_call(
      gas,
      registers,
      memory,
      context,
      &historical_lookup_pure/6,
      [index, service_accounts, timeslot]
    )
  end



  def import(gas, registers, memory, context, import_segments) do
    wrap_host_call(gas, registers, memory, context, &import_pure/4, [import_segments])
  end

  def export(gas, registers, memory, context, {m, export_segments}, export_offset) do
    wrap_host_call(gas, registers, memory, context, &export_pure/4, [
      {m, export_segments},
      export_offset
    ])
  end

  def machine(gas, registers, memory, context) do
    wrap_host_call(gas, registers, memory, context, &machine_pure/3, [])
  end

  def peek(gas, registers, memory, context) do
    wrap_host_call(gas, registers, memory, context, &peek_pure/3, [])
  end

  def poke(gas, registers, memory, context) do
    wrap_host_call(gas, registers, memory, context, &poke_pure/3, [])
  end

  def zero(gas, registers, memory, context) do
    wrap_host_call(gas, registers, memory, context, &zero_pure/3, [])
  end
end
