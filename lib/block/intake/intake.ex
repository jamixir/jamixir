defmodule Block.Intake.Intake do
  alias Jamixir.NodeStateServer
  alias Block
  alias Block.Header
  alias Network.{Connection, ConnectionManager}
  alias Storage
  alias Util.Logger
  import Codec.Encoder
  import Util.Hex, only: [b16: 1]

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

          # Case B: Parent exists → request announced block only
          Storage.has_block?(header.parent_hash) ->
            Logger.debug("[ANNOUNCE] Parent exists, requesting block #{b16(header_hash)}")
            fetch_blocks_and_decide(header_hash, announcing_peer)

          # Case C: Parent missing → request ancestors and the announced block
          true ->
            gap_estimate = estimate_gap_size(announced_slot)

            Logger.debug(
              "[ANNOUNCE] Parent missing, requesting ancestors for #{b16(header_hash)} parent=#{b16(header.parent_hash)} gap_estimate=#{gap_estimate}"
            )

            fetch_blocks_and_decide(header_hash, announcing_peer, gap_estimate)
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

  defp estimate_gap_size(announced_slot) do
    latest_slot = Storage.get_latest_timeslot()
    max(announced_slot - latest_slot, 1)
  end

  defp fetch_blocks_and_decide(header_hash, announcing_peer, gap_estimate \\ 1) do
    Task.start(fn ->
      case Connection.request_blocks(announcing_peer, header_hash, 1, gap_estimate) do
        {:ok, blocks} when is_list(blocks) ->
          Logger.debug("[BATCH_RECEIVED] received #{length(blocks)} blocks")

          # Recursively fetch ancestors until we reach a block we have
          all_blocks = fetch_missing_ancestors(blocks, announcing_peer, gap_estimate)

          # blocks are inserted to storage first thing and in all cases
          # so we can use the storage layer to decide the best fork and apply the blocks
          # pruning is still a TODO (probably best done after finality is implemented)

          insert_blocks(all_blocks)
          maybe_advance_chain(header_hash, all_blocks)

        {:error, reason} ->
          Logger.error("Failed to request ancestor blocks: #{inspect(reason)}")
      end
    end)
  end

  defp fetch_missing_ancestors(blocks, announcing_peer, gap_estimate, max_iterations \\ 10) do
    oldest_block = List.last(blocks)
    oldest_parent = oldest_block.header.parent_hash

    cond do
      max_iterations <= 0 ->
        Logger.warning("[FETCH_ANCESTORS] Max iterations reached, chain may be incomplete")
        blocks

      Storage.has_block?(oldest_parent) ->
        blocks

      true ->
        case Connection.request_blocks(announcing_peer, oldest_parent, 1, gap_estimate) do
          {:ok, more_blocks} when is_list(more_blocks) and length(more_blocks) > 0 ->
            all_blocks = blocks ++ more_blocks
            fetch_missing_ancestors(all_blocks, announcing_peer, gap_estimate, max_iterations - 1)

          {:ok, []} ->
            Logger.warning("[FETCH_ANCESTORS] No more blocks available from peer")
            blocks

          {:error, reason} ->
            Logger.error("[FETCH_ANCESTORS] Failed to request ancestors: #{inspect(reason)}")
            blocks
        end
    end
  end

  defp insert_blocks(blocks) do
    Enum.each(blocks, &Storage.put(&1))
  end

  defp maybe_advance_chain(header_hash, blocks) do
    canonical_tip = Storage.get_canonical_tip()

    case Storage.get_canonical_root(header_hash) do
      {:ok, canonical_root} ->
        decide_fork_action(canonical_root, canonical_tip, blocks)

      _error ->
        Logger.error("""
        [FORK/INVARIANT_VIOLATION]
        No canonical root found.

        incoming_tip=#{b16(header_hash)}
        canonical_tip=#{b16(canonical_tip)}

        THIS MUST NEVER HAPPEN.
        """)

        throw("NO_CANONICAL_ROOT")
    end
  end

  defp decide_fork_action(canonical_root, canonical_tip, blocks) do
    {:ok, canonical_tip_from_root} =
      Storage.get_heaviest_chain_tip_from_canonical_root(canonical_root)

    cond do
      # FORWARD EXTENSION (no fork)
      #   applied ──► applied ──► applied (= canonical_tip = canonical_root)
      #                                      │
      #                                      └──► incoming ──► incoming
      canonical_root == canonical_tip ->
        Logger.debug("Root of incoming chain is canonical tip, applying all blocks forward")

        apply_forward(blocks)

      # INCOMING FORK LOSES (tie or lighter)
      # incoming chain has less or equel block from the canonical root to the tip (is lighter)
      #           applied ──► applied ──► applied (= canonical_tip)
      #                ▲
      #                │
      #   applied ──► canonical_root
      #                │
      #                └──► incoming ──► incoming   (losing fork)

      canonical_tip_from_root == canonical_tip ->
        Logger.debug(
          "Incoming chain lost, we are on the best fork, nothing to do (except prune later)"
        )

        :ok

      # REORG REQUIRED (incoming fork wins)
      #             applied ──► applied (= canonical_tip)
      #                ▲
      #                │
      #   applied ──► canonical_root ──► incoming ──► incoming (= canonical_tip_from_root)
      true ->
        Logger.debug("""
        [REORG] Chain reorganization required!
        canonical_root: #{b16(canonical_root)}
        old_canonical_tip: #{b16(canonical_tip)}
        new_canonical_tip: #{b16(canonical_tip_from_root)}
        """)

        perform_reorg(canonical_root, canonical_tip, blocks)
    end
  end

  defp perform_reorg(canonical_root, old_canonical_tip, incoming_blocks) do
    # Move state back to canonical root
    unwind_to_canonical_root(canonical_root, old_canonical_tip)
    Logger.debug("[REORG] Successfully unwound to canonical root")

    # Apply forward from canonical root
    # Filter incoming_blocks to exclude canonical_root and any blocks older than it
    # incoming_blocks are in newest-first order (as fetched from network)
    blocks_to_apply = take_blocks_after_root(incoming_blocks, canonical_root)
    Logger.info("[REORG] Applying #{length(blocks_to_apply)} blocks from new chain")
    apply_forward(blocks_to_apply)
    Logger.debug("[REORG] Chain reorganization completed successfully")
    :ok
  end

  defp take_blocks_after_root(blocks, canonical_root) do
    Enum.take_while(blocks, fn block ->
      h(e(block.header)) != canonical_root
    end)
  end

  defp unwind_to_canonical_root(canonical_root, old_canonical_tip) do
    # Load state at canonical root
    state_at_root = Storage.get_state(canonical_root)

    # Set canonical tip to canonical root
    Storage.set_canonical_tip(canonical_root)

    # Set state to canonical root state
    NodeStateServer.set_jam_state(state_at_root)

    # Mark old chain as unapplied
    :ok = Storage.unmark_between(old_canonical_tip, canonical_root)
    :ok
  end

  defp apply_forward(blocks) do
    blocks
    |> Enum.reverse()
    |> Enum.each(fn block ->
      case NodeStateServer.add_block(block, false) do
        {:ok, _new_state} ->
          :ok

        {:error, reason} ->
          header_hash = b16(h(e(block.header)))
          Logger.error("Failed to add block #{header_hash} to state: #{inspect(reason)}")
      end
    end)
  end
end
