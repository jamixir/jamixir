defmodule System.DataAvailability.SegmentData do
  @type t :: %__MODULE__{
          erasure_root: Types.hash(),
          segment_index: non_neg_integer(),
          data: binary()
        }

  defstruct [:erasure_root, :segment_index, :data]

  defimpl Encodable do
    alias System.DataAvailability.SegmentData

    def encode(%SegmentData{} = sd), do: sd.data
  end
end
