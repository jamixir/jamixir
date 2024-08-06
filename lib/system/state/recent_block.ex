defmodule System.State.RecentBlock do
  alias Block.Header

  @type hash :: <<_::256>>

  @type t :: %__MODULE__{
          header_hash: hash,
          accumulated_result_mmr: list(hash | nil),
          state_root: hash,
          work_reports_hashes: list(hash)
        }

  # Equation (81)
  defstruct header_hash: nil,
            accumulated_result_mmr: [nil],
            state_root: nil,
            work_reports_hashes: [nil]

  # Equation (17) Equation (82)
  def get_initial_block_history(%Header{prior_state_root: _s}, nil), do: []
  def get_initial_block_history(%Header{prior_state_root: _s}, []), do: []

  def get_initial_block_history(%Header{prior_state_root: s}, blocks) do
    case Enum.split(blocks, length(blocks) - 1) do
      {init, [last_block]} ->
        modified_last_block = %__MODULE__{last_block | state_root: s}
        init ++ [modified_last_block]
    end
  end
end
