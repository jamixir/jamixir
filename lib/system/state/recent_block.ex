defmodule System.State.RecentBlock do
  alias Block.Header

  @type t :: %__MODULE__{
          header_hash: binary(),
          accumulated_result: list(binary()),
          state_root: binary(),
          work_reports_hashes: list(binary())
        }

  # Equation (81)
  defstruct [
    header_hash: nil,
    accumulated_result: nil,
    state_root: nil,
    work_reports_hashes: nil,
  ]

  # Equation (17) Equation (82)
  def get_initial_block_history(%Header{prior_state_root: s}, nil), do: []
  def get_initial_block_history(%Header{prior_state_root: s}, []), do: []
  def get_initial_block_history(%Header{prior_state_root: s}, [most_recent_block | other_blocks]) do
    modified_first_block = %__MODULE__{most_recent_block | state_root: s}
    [modified_first_block | other_blocks]
  end
end
