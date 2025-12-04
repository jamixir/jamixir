defmodule Network.Types.SegmentShardsRequest do
  @type t :: %__MODULE__{
          erasure_root: Types.hash(),
          shard_index: non_neg_integer(),
          segment_indexes: list(non_neg_integer())
        }

  defstruct [:erasure_root, :shard_index, :segment_indexes]
end
