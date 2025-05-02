defmodule Network.Types.SegmentShardsRequest do
  @type t :: %__MODULE__{
          erasure_root: Types.hash(),
          segment_index: non_neg_integer(),
          shard_indexes: list(non_neg_integer())
        }

  defstruct [:erasure_root, :segment_index, :shard_indexes]
end
