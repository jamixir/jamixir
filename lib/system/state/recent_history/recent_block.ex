defmodule System.State.RecentHistory.RecentBlock do
  @type t :: %__MODULE__{
          # h
          header_hash: Types.hash(),
          # b
          accumulated_result_mmr: list(Types.hash() | nil),
          # s
          state_root: Types.hash(),
          # p
          work_report_hashes: %{Types.hash() => Types.hash()}
        }

  # Formula (81) v0.4.1
  defstruct header_hash: nil,
            accumulated_result_mmr: [nil],
            state_root: nil,
            work_report_hashes: %{}
end
