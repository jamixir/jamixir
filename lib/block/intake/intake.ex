defmodule Block.Intake.Intake do
  @moduledoc """
  Block intake layer - single entry point for block announcements.

  Coordinates:
  - Block storage inspection
  - Missing ancestor detection
  - Parent request decision
  - CE 128 network execution

  Preserves announcer identity for prioritized parent requests.
  """

  alias Jamixir.NodeStateServer
  alias Block
  alias Block.Header
  alias Block.Intake.Decision
  alias Network.{Connection, ConnectionManager}
  alias Storage
  alias Util.Logger
  import Codec.Encoder
  import Util.Hex, only: [b16: 1]

  @doc """
  Process a block announcement from a peer.

  ## Parameters
  - `header`: The announced block header (UP 0 announcement contains header only)
  - `remote_ed25519_key`: Ed25519 key of the peer that sent the announcement

  ## Decision Logic

  Case A — Block already exists:
  - Ignore (duplicate announcement)

  Case B — Parent exists:
  - Request THIS block only via CE 128
  - direction = 1, max_blocks = 1, starting at this block hash
  - We already have the parent, we only lack the announced block body

  Case C — Parent missing:
  - Estimate gap size using slot numbers
  - Request N blocks via CE 128 (ancestors)
  - direction = 1, max_blocks = estimated_gap
  - Queue results for ordered processing (old → new)
  - After ancestors processed, request the announced block itself
  """
  @spec process_announcement(Header.t(), binary()) :: :ok
  def process_announcement(%Header{} = header, remote_ed25519_key) do
    header_hash = h(e(header))
    announced_slot = header.timeslot

    # Get the connection PID for this peer
    case ConnectionManager.get_connection(remote_ed25519_key) do
      {:ok, announcing_peer} ->
        cond do
          # Case A: Block already exists → ignore
          Storage.has_block?(header_hash) ->
            Logger.debug("[ANNOUNCE] Block #{b16(header_hash)} already exists, ignoring")
            :ok

          # Case B: Parent exists → request THIS block only
          Storage.has_block?(header.parent_hash) ->
            Logger.debug("[ANNOUNCE] Parent exists, requesting block #{b16(header_hash)}")
            request_block(header_hash, announcing_peer)

          # Case C: Parent missing → request ancestors with gap-aware batch size, then fetch announced block
          true ->
            Logger.debug(
              "[ANNOUNCE] Parent missing, requesting ancestors for #{b16(header_hash)}"
            )

            gap_estimate = estimate_gap_size(announced_slot)

            request_missing_parents(
              header_hash,
              header.parent_hash,
              gap_estimate,
              announcing_peer
            )
        end

      {:error, :not_found} ->
        Logger.warning(
          "Cannot process announcement: connection not found for peer (key: #{b16(remote_ed25519_key)})"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "Cannot process announcement: connection error for peer: #{inspect(reason)}"
        )

        :ok
    end
  end

  # Estimate gap size based on slot difference between announced block and our latest
  defp estimate_gap_size(announced_slot) do
    case Storage.get_latest_header() do
      nil ->
        # No local blocks yet, request up to max
        announced_slot

      {latest_slot, _header} ->
        # Gap = announced slot - our latest slot
        # Add buffer for potential forks/skipped slots
        max(announced_slot - latest_slot, 1)
    end
  end

  # Request the announced block only (parent exists, we just need the block body)
  defp request_block(header_hash, announcing_peer) do
    # CE 128: direction = 1 (descending), max_blocks = 1, starting at this block hash
    Task.start(fn ->
      case Connection.request_blocks(announcing_peer, header_hash, 1, 1) do
        {:ok, [block]} ->
          process_received_block(block)

        {:ok, []} ->
          Logger.warning("No blocks returned for request: #{b16(header_hash)}")

        {:error, reason} ->
          Logger.error("Failed to request block #{b16(header_hash)}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  # Request missing parent blocks using CE 128, then fetch the announced block
  # Uses gap_estimate to request appropriate number of blocks in single batch
  defp request_missing_parents(announced_header_hash, parent_hash, gap_estimate, announcing_peer) do
    # Use decision logic to determine what to request
    case Decision.decide(announcing_peer, gap_estimate) do
      {:request_blocks, peer, direction, max_blocks} ->
        Logger.info(
          "[BATCH_REQUEST] requesting #{max_blocks} blocks starting from #{b16(parent_hash)}"
        )

        Task.start(fn ->
          case Connection.request_blocks(peer, parent_hash, direction, max_blocks) do
            {:ok, blocks} when is_list(blocks) ->
              Logger.info("[BATCH_RECEIVED] received #{length(blocks)} blocks")

              # Process received ancestor blocks (old → new)
              # Blocks arrive in descending order (newest first), so reverse for old→new processing
              blocks
              |> Enum.reverse()
              |> Enum.each(&process_received_block/1)

              # Now fetch and process the originally announced block
              fetch_and_process_announced_block(announced_header_hash, peer)

            {:ok, result} ->
              Logger.warning("Unexpected result from request_blocks: #{inspect(result)}")

            {:error, reason} ->
              Logger.error("Failed to request ancestor blocks: #{inspect(reason)}")
          end
        end)

      # :defer means "do nothing now"
      :defer ->
        :ok
    end

    :ok
  end

  # Fetch the originally announced block after ancestors have been processed
  defp fetch_and_process_announced_block(header_hash, peer) do
    if Storage.has_block?(header_hash) do
      Logger.info("[CASCADE_SKIP] block=#{b16(header_hash)} already applied via cascade")
      :ok
    else
      case Connection.request_blocks(peer, header_hash, 1, 1) do
        {:ok, [block]} ->
          Logger.info(
            "[CASCADE_FETCH] block=#{b16(header_hash)} fetching after ancestors applied"
          )

          process_received_block(block)

        {:ok, []} ->
          Logger.warning("[CASCADE_FETCH] block=#{b16(header_hash)} not returned by peer")

        {:error, reason} ->
          Logger.error(
            "[CASCADE_FETCH] Failed to fetch block #{b16(header_hash)}: #{inspect(reason)}"
          )
      end
    end
  end

  # Process a block received via CE 128 response
  defp process_received_block(%Block{} = block) do
    header_hash = h(e(block.header))

    # Skip if we already have this block (avoids duplicate processing in batch scenarios)
    if Storage.has_block?(header_hash) do
      Logger.debug("[BLOCK_RX_SKIP] block=#{b16(header_hash)} already exists")
      :ok
    else
      missing = Storage.missing_ancestors(block.header)
      Logger.info("[BLOCK_RX] block=#{b16(header_hash)} missing=#{length(missing)}")

      case missing do
        [] ->
          apply_block(block)

        _ ->
          Storage.save_pending_block(block)
      end
    end
  end

  # Apply a block (parent is available)
  # TODO: implement block application logic
  defp apply_block(%Block{} = block) do
    # header_hash = h(e(block.header))
    # parent_hash = block.header.parent_hash

    # # Use NodeStateServer to add block (integrates with existing flow)
    # # Returns {:ok, new_state} on success, or updates state internally on error
    # case NodeStateServer.add_block(block, false) do
    #   {:ok, _new_state} ->
    #     # Remove from pending_blocks if it was there
    #     Storage.remove_pending_block(header_hash)

    #     Logger.info(
    #       "[BLOCK_APPLIED] block=#{b16(header_hash)} parent=#{b16(parent_hash)} - committed to canonical chain"
    #     )

    #     # Cascade: Check if any pending blocks were waiting for this block
    #     process_pending_blocks_for_parent(header_hash)

    #   error ->
    #     Logger.error("Failed to apply block #{b16(header_hash)}: #{inspect(error)}")
    # end
  end

  # Process pending blocks that were waiting for a parent that just became available
  # TODO: implement pending block processing when Storage functions are available
  defp process_pending_blocks_for_parent(parent_hash) do
    # Get all pending blocks waiting for this parent
    pending_blocks = Storage.get_pending_blocks_by_parent(parent_hash)

    # Process each pending block (they are already ordered by slot)
    Enum.each(pending_blocks, fn block ->
      apply_block(block)
    end)
  end
end
