defmodule PVM.Host do
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
  alias PVM.Memory

  # ΩG: Gas-remaining host-call.
  @callback remaining_gas(
              gas :: non_neg_integer(),
              registers :: list(non_neg_integer()),
              args :: term()
            ) :: any()
  def remaining_gas(gas, registers, args \\ []) do
    g = 10

    if gas < g do
      {:out_of_gas, 0, registers, args}
    else
      #  place gas-g on registers[7]
      registers = List.update_at(registers, 7, fn _ -> gas - g end)

      {:continue, gas - g, registers, args}
    end
  end

  # ΩL: Lookup-preimage host-call.
  # ΩR: Read-storage host-call.
  # ΩW : Write-storage host-call.
  # ΩI: Information-on-servicehost-call.
end
