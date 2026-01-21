defmodule Block.Intake.Decision do
  @moduledoc """
  Decision logic for block intake requests.

  Determines how many blocks to request based on:
  - Number of known missing ancestors
  - Estimated gap size from slot numbers
  - Configurable limits to prevent excessive requests
  """

  @type peer :: pid()
  # 1 is descending inclusive direction (https://docs.jamcha.in/knowledge/advanced/simple-networking/spec#ce-128-block-request)
  @type decision :: {:request_blocks, peer(),  1, pos_integer()} | :defer

  @doc """
  Decide what blocks to request based on missing ancestors and gap estimate.

  Uses the larger of:
  - Known missing ancestors count
  - Slot-based gap estimate (more accurate for large gaps)

  Capped by max_blocks_limit for safety.
  """
  @spec decide(peer() | term(), non_neg_integer()) :: decision()
  def decide(announcing_peer, gap_estimate)
      when is_pid(announcing_peer) do
    # Cap at configured maximum
    max_blocks = min(gap_estimate, max_blocks_limit())

    {:request_blocks, announcing_peer, 1, max_blocks}
  end

  def decide(_announcing_peer, _gap_estimate) do
    # Invalid inputs: non-pid peer, empty list, or non-list
    :defer
  end

  # Maximum blocks to request in a single CE128 call.
  # Configurable via :jamixir, :block_intake_max_request_blocks

  defp max_blocks_limit do
    Application.get_env(:jamixir, :block_intake_max_request_blocks, 50)
  end
end
