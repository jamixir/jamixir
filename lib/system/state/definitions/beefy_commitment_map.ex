defmodule System.State.BeefyCommitmentMap do
  @moduledoc """
  A set of tuples, each tuple containing a service index and an accumulation-result tree root.
  See section 12.4
  """

  # Formula (176) v0.4.5
  @type t :: MapSet.t({non_neg_integer(), Types.hash()})
  def new(list), do: MapSet.new(list)
end
