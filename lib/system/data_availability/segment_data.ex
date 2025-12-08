defmodule System.DataAvailability.SegmentData do
  @type t :: %__MODULE__{
          merkle_root: Types.hash(),
          segment_index: non_neg_integer(),
          data: binary()
        }

  defstruct [:merkle_root, :segment_index, :data]

  defimpl Encodable do
    alias System.DataAvailability.SegmentData

    def encode(%SegmentData{} = sd), do: sd.data
  end
end
