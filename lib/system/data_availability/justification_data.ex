defmodule System.DataAvailability.JustificationData do
  @type t :: %__MODULE__{
          erasure_root: Types.hash(),
          segment_index: non_neg_integer(),
          data: binary()
        }

  defstruct [:erasure_root, :segment_index, :data]
end
