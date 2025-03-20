defmodule System.State.BeefyCommitmentMap do
  # Formula (12.15) v0.6.4
  @type t :: MapSet.t({non_neg_integer(), Types.hash()})
  def new(list), do: MapSet.new(list)
end
