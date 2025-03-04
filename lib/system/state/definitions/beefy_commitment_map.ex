defmodule System.State.BeefyCommitmentMap do
  @moduledoc """
  See section 12.21
  """

  @type t :: MapSet.t({non_neg_integer(), Types.hash()})
  def new(list), do: MapSet.new(list)
end
