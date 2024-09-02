defmodule RingVRF.RingCommitment do
  @enforce_keys [:points, :ring_selector]
  defstruct points: [], ring_selector: nil
end
