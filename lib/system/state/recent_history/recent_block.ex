defmodule System.State.RecentHistory.RecentBlock do
  @type t :: %__MODULE__{
          header_hash: Types.hash(),
          accumulated_result_mmr: list(Types.hash() | nil),
          state_root: Types.hash(),
          work_report_hashes: list(Types.hash())
        }

  # Formula (81) v0.3.4
  defstruct header_hash: nil,
            accumulated_result_mmr: [nil],
            state_root: nil,
            work_report_hashes: [nil]
end
