defmodule Jamixir.Node do
  alias Block.Extrinsic.TicketProof
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.WorkPackage
  alias Jamixir.NodeStateServer
  alias Network.ConnectionManager
  alias System.State
  alias Util.Hash
  use StoragePrefix
  import Util.Hex, only: [b16: 1]
  import Codec.Encoder
  alias Jamixir.Genesis
  alias Util.Logger

  @behaviour Jamixir.NodeAPI

  @impl true
  def add_block(block_binary) when is_binary(block_binary) do
    {block, _} = Block.decode(block_binary)
    add_block(block)
  end

  def add_block(%Block{} = block) do
    case Storage.get_state(block.header.parent_hash) do
      nil ->
        Logger.error("Parent state not found for hash: #{b16(block.header.parent_hash)}")
        {:error, nil, :parent_state_not_found}

      app_state ->
        add_block(block, app_state)
    end
  end

  def add_block(%Block{} = block, %State{} = state) do
    case State.add_block(state, block) do
      {:ok, new_app_state} ->
        state_root = Storage.put(block, new_app_state)
        Storage.put(block)
        {:ok, new_app_state, state_root}

      {:error, pre_state, reason} ->
        {:error, pre_state, reason}
    end
  end

  @impl true
  def announce_block(header, _latest_hash, _latest_timeslot) do
    hash = h(e(header))
    pid = self()

    Task.start(fn ->
      Logger.debug("Requesting block #{b16(hash)} back from author")
      {:ok, [b]} = Network.Connection.request_blocks(pid, hash, 1, 1)
      NodeStateServer.add_block(b, false)
    end)

    :ok
  end

  @impl true
  def inspect_state(header_hash) do
    case Storage.get_state(header_hash) do
      nil -> {:error, :no_state}
      state -> {:ok, state}
    end
  end

  @impl true
  def inspect_state(header_hash, key) do
    case Storage.get_state(header_hash, key) do
      nil -> {:error, :no_state}
      value -> {:ok, value}
    end
  end

  def load_state(path) do
    case Codec.State.from_file(path) do
      {:ok, state} ->
        Storage.put(Genesis.genesis_block_header(), state)
        :ok

      {:error, reason} ->
        Logger.error("Failed to load state from #{path}: #{reason}")
        {:error, reason}
    end
  end

  # CE 128 - Block Request
  @impl true
  def get_blocks(_, _, 0), do: {:ok, []}

  def get_blocks(header_hash, :descending, count) do
    {blocks, _} =
      Enum.reduce_while(1..count, {[], header_hash}, fn _, {blocks, next_hash} ->
        case Storage.get_block(next_hash) do
          nil ->
            {:halt, {blocks, nil}}

          block ->
            {:cont, {blocks ++ [block], block.header.parent_hash}}
        end
      end)

    {:ok, blocks}
  end

  def get_blocks(header_hash, :ascending, count) do
    {blocks, _} =
      Enum.reduce_while(1..count, {[], header_hash}, fn _, {blocks, next_hash} ->
        case Storage.get_next_block(next_hash) do
          nil ->
            {:halt, {blocks, nil}}

          child_hash ->
            case Storage.get_block(child_hash) do
              nil -> {:halt, {blocks, nil}}
              block -> {:cont, {[block | blocks], h(e(block.header))}}
            end
        end
      end)

    {:ok, Enum.reverse(blocks)}
  end

  # CE 142 - Preimage Announcement
  @impl true
  def receive_preimage(_service_id, hash, _length) do
    server_pid = self()

    Task.start(fn ->
      Logger.info(
        "Requesting preimage #{b16(hash)} back from client via server #{inspect(server_pid)}"
      )

      Network.Connection.get_preimage(server_pid, hash)
    end)

    :ok
  end

  # CE 143 - Preimage Request
  @impl true
  def get_preimage(hash) do
    case Storage.get("#{@p_preimage}#{hash}") do
      nil ->
        {:error, :not_found}

      preimage ->
        {:ok, preimage}
    end
  end

  @impl true
  def save_preimage(preimage) do
    Storage.put("#{@p_preimage}#{Hash.default(preimage)}", preimage)
    :ok
  end

  # CE 141 - Assurance distribution
  @impl true
  def save_assurance(assurance) do
    Storage.put(assurance)
  end

  # CE 131 - Safrole ticket distribution
  @impl true
  def process_ticket(:proxy, epoch, ticket) do
    state = get_latest_state()

    case TicketProof.proof_output(ticket, state.entropy_pool.n2, state.safrole.epoch_root) do
      {:error, _} ->
        Logger.debug("Invalid ticket received at proxy for epoch #{epoch}. Ignoring.")

      {:ok, _} ->
        Storage.put(epoch, ticket)

        for {_v, pid} <- NodeStateServer.instance().current_connections() do
          Network.Connection.distribute_ticket(pid, :validator, epoch, ticket)
        end
    end

    :ok
  end

  # CE 132 - Safrole ticket distribution
  @impl true
  def process_ticket(:validator, epoch, ticket) do
    Storage.put(epoch, ticket)
  end

  # CE 145 - Judgment publication
  @impl true
  def save_judgement(epoch, hash, judgement) do
    if not judgement.vote do
      for {_v, pid} <- NodeStateServer.instance().neighbours() do
        Network.Connection.announce_judgement(pid, epoch, hash, judgement)
      end
    end

    Storage.put(judgement, hash, epoch)

    :ok
  end

  # CE 135 - Work-report Guarantee distribution
  @impl true
  def save_guarantee(guarantee) do
    spec = guarantee.work_report.specification
    Logger.info("Saving guarantee for work report: #{b16(spec.work_package_hash)}")
    Storage.put("#{@p_guarantee}#{spec.work_package_hash}", guarantee)

    _server_pid = self()
    header_hash = <<>>

    case Storage.get_state(header_hash) do
      nil ->
        Logger.error("No state found to request erasure code for work report")
        {:error, :no_state}

      _state ->
        Task.start(fn ->
          Logger.info("Request EC  for work report: #{b16(spec.work_package_hash)}")

          # Network.Connection.request_audit_shard(
          #   server_pid,
          #   spec.erasure_root,
          #   NodeStateServer.assigned_shard_index(guarantee.work_report.core_index)
          # )
        end)
    end

    :ok
  end

  # CE 136 - Work-report request
  @impl true
  def get_work_report(hash) do
    case Storage.get("#{@p_guarantee}#{hash}") do
      nil -> {:error, :not_found}
      guarantee -> {:ok, guarantee.work_report}
    end
  end

  # CE 133 - Work-package submission
  @impl true
  def save_work_package(wp, core, extrinsics) do
    if WorkPackage.valid_extrinsics?(wp, extrinsics) do
      Storage.put(wp, core)

      for e <- extrinsics do
        Storage.put(e)
      end

      process_work_package(wp, core, extrinsics)

      :ok
    else
      Logger.error("Invalid extrinsics for work package service #{wp.service} core #{core}")
      {:error, :invalid_extrinsics}
    end
  end

  def get_latest_state do
    {_ts, header} = Storage.get_latest_header()
    Storage.get_state(header)
  end

  def process_work_package(wp, core, _extrinsics) do
    Logger.info("Processing work package for service #{wp.service} core #{core}")

    services = get_latest_state().services

    case WorkReport.execute_work_package(wp, core, services) do
      :error ->
        Logger.error("Failed to execute work package for service #{wp.service} core #{core}")
        {:error, :execution_failed}

      # Auth logic and import segments ok. share with other guarantors
      {_import_segments, refine_task} ->
        # send WP bundle to two other guarantors in same core through CE 134
        bundle_bin = Encodable.encode(WorkPackage.bundle(wp))
        {work_report, _exports} = Task.await(refine_task)
        Logger.info("Work package validated successfully. Sending to other guarantors")

        validators = NodeStateServer.same_core_guarantors()

        responses =
          for v <- validators do
            pid = ConnectionManager.get_connection(v.ed25519)

            # TODO send correct segment lookup map
            {v.ed25519, Network.Connection.send_work_package_bundle(pid, bundle_bin, core, %{})}
          end

        wr_hash = h(e(work_report))

        case Enum.filter(responses, fn {_, {:ok, {hash, _}}} -> hash == wr_hash end) do
          [] ->
            Logger.warning("No other guarator confirmed work report")

          list ->
            credentials =
              for {pub_key, {:ok, {_, signature}}} <- list do
                {NodeStateServer.validator_index(pub_key), signature}
              end

            guarantee = %Guarantee{
              work_report: work_report,
              # TODO review what timeslot to use
              timeslot: NodeStateServer.current_timeslot(),
              credentials: credentials
            }

            # send guarantee to all validators
            for pid <- ConnectionManager.get_connections() do
              Network.Connection.distribute_guarantee(pid, guarantee)
            end
        end

        # TODO
        # erasure code exports and save for upcoming calls
        :ok
    end
  end

  # CE 134 - Work-package sharing
  @impl true
  def save_work_package_bundle(bundle, core, _segment_lookup_dict) do
    Logger.info("Saving work package bundle for core #{core}")

    # Save all import segments locally
    for wi <- bundle.work_package.work_items do
      for {hash, index} <- wi.import_segments do
        case Enum.find(bundle.import_segments, fn {h, _} -> h == hash end) do
          nil ->
            Logger.warning("Import segment #{b16(hash)} not found in bundle")

          {segment_bin, _} ->
            Storage.put_segment(hash, index, segment_bin)
        end
      end

      # Save all extrinsics locally
      for e <- wi.extrinsics, do: Storage.put(e)

      # Verify and save all justifications
      # TODO
    end

    process_work_package(bundle.work_package, core, bundle.extrinsics)
    # Execute refine, calculate wp hash and returns signature if sucessful
  end

  # CE 144 - Audit announcement
  @impl true
  def save_audit(_audit) do
    {:error, :not_implemented}
  end

  # CE 137 - Work Report Shard Request
  @impl true
  def get_work_report_shard(_erasure_root, _segment_index) do
    {:error, :not_implemented}
  end

  # CE 139/140: Segment shard request
  @impl true
  def get_segment_shards(_erasure_root, _segment_index, _shard_index) do
    {:error, :not_implemented}
  end

  # CE 129 - State request
  @impl true
  def get_state_trie(_header_hash) do
    {:error, :not_implemented}
  end

  @impl true
  def get_justification(_erasure_root, _segment_index, _shard_index) do
    {:error, :not_implemented}
  end
end
