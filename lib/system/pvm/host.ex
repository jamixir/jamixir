defmodule System.PVM.Host do
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
  alias System.PVM.Memory

  # ΩG: Gas-remaining host-call.
  @callback remaining_gas(
              gas :: non_neg_integer(),
              registers :: list(non_neg_integer()),
              memory :: Memory.t()
            ) :: any()
  def remaining_gas(g, [w0, w1, w2, w3, w4, w5, w6, _w7, _w8 | rest], memory) do
    g_ = g - 10
    w7_ = rem(g_, 4_294_967_296)
    w8_ = div(g_, 4_294_967_296)
    {g, [w0, w1, w2, w3, w4, w5, w6, w7_, w8_ | rest], memory}
  end

  # ΩL: Lookup-preimage host-call.
  # ΩR: Read-storage host-call.
  # ΩW : Write-storage host-call.
  # ΩI: Information-on-servicehost-call.
end
