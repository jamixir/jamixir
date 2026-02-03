defmodule Jamixir.Node do
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.TicketProof
  alias Block.Extrinsic.WorkPackage
  alias Jamixir.Genesis
  alias Jamixir.NodeStateServer
  alias Network.ConnectionManager
  alias Storage.PreimageMetadataRecord
  alias System.State
  alias Util.Crypto
  alias Util.Logger
  alias Util.MerkleTree
  use StoragePrefix
  import Util.Hex, only: [b16: 1]
  import Codec.Encoder

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
  def receive_preimage(service_id, hash, length) do
    server_pid = self()

    Storage.put(%PreimageMetadataRecord{
      service_id: service_id,
      hash: hash,
      length: length,
      status: :pending
    })

    Task.start(fn ->
      Logger.info(
        "Requesting preimage #{b16(hash)} back from client via server #{inspect(server_pid)}"
      )

      :ok = Network.Connection.get_preimage(server_pid, hash)
    end)

    :ok
  end

  # CE 143 - Preimage Request
  @impl true
  def get_preimage(hash) do
    Storage.get_preimage(hash)
  end

  @impl true
  def save_preimage(%Preimage{blob: b, service: s} = p) do
    Logger.info("Saving preimage (hash: #{b16(h(b))}) for service #{s}")
    Storage.put(p)
    :ok
  end

  @impl true
  def save_preimage(blob) when is_binary(blob) do
    Logger.info("Saving preimage (hash: #{b16(h(blob))})")
    Storage.put(@p_preimage <> h(blob), blob)
    :ok
  end

  # CE 141 - Assurance distribution
  @impl true
  def save_assurance(assurance) do
    connections = ConnectionManager.instance().get_connections()

    case Enum.find(connections, fn {_, pid} -> pid == self() end) do
      nil ->
        Logger.warning("connection not found, can't figure out validator index")
        {:error, :validator_connection_not_found}

      {k, _} ->
        case NodeStateServer.instance().validator_index(k) do
          nil ->
            {:error, :validator_key_not_found}

          validator_index ->
            # TODO should also verify assurance signature here
            {:ok, Storage.put(%Assurance{assurance | validator_index: validator_index})}
        end
    end
  end

  # CE 131 - Safrole ticket distribution
  @impl true
  def process_ticket(:proxy, epoch, ticket) do
    state = get_latest_state()

    case TicketProof.proof_output(ticket, state.entropy_pool.n1, state.safrole.epoch_root) do
      {:error, _} ->
        Logger.debug("Invalid ticket received at proxy for epoch #{epoch}. Ignoring.")

      {:ok, _} ->
        if Enum.any?(Storage.get_tickets(epoch), &(&1 == ticket)) do
          Logger.debug("Duplicate ticket received at proxy for epoch #{epoch}. Ignoring.")
        else
          connections = ConnectionManager.instance().get_connections()
          Logger.debug("🎟️ Forwarding ticket to #{map_size(connections)} validators.")

          for {_, pid} <- connections do
            Task.start(fn ->
              Logger.debug("🎟️ Forwarding ticket to validator #{inspect(pid)}")
              Network.Connection.distribute_ticket(pid, :validator, epoch, ticket)
            end)
          end

          Storage.put(epoch, ticket)
        end
    end

    :ok
  end

  # CE 132 - Safrole ticket distribution
  @impl true
  def process_ticket(:validator, epoch, ticket) do
    Logger.info(
      "🎟️ Received ticket [#{ticket.attempt}, #{b16(ticket.signature)}]} for epoch #{epoch}"
    )

    Storage.put(epoch, ticket)
    :ok
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
    wr = guarantee.work_report
    Storage.put(guarantee)

    # TODO
    # this is not the final solution. Just a workaround to force
    # assurances fetch after guarantee is on state
    pid = self()

    Task.start(fn ->
      Logger.info(
        "Requesting work report shards for work report #{b16(h(e(wr)))} from guarantors"
      )

      NodeStateServer.instance().fetch_work_report_shards(pid, wr)
    end)

    :ok
  end

  # CE 136 - Work-report request
  @impl true
  def get_work_report(hash) do
    case Storage.get_work_report(hash) do
      nil -> {:error, :not_found}
      work_report -> {:ok, work_report}
    end
  end

  # CE 133 - Work-package submission
  @impl true
  def save_work_package(wp, core, extrinsics) do
    # extrinsics are sent in a single list of binaries
    # this function validates them against the work package and organizes them per work item
    case WorkPackage.organize_extrinsics(wp, extrinsics) do
      {:ok, org_extrinsics} ->
        Storage.put(wp, core)
        for e <- extrinsics, do: Storage.put(e)
        process_work_package(wp, core, org_extrinsics)

      {:error, e} ->
        Logger.error("Invalid extrinsics for work package service #{wp.service} core #{core}")
        {:error, e}
    end
  end

  def get_latest_state do
    {_ts, header} = Storage.get_latest_header()
    Storage.get_state(header)
  end

  def process_work_package(wp, core, extrinsics) do
    Logger.info("Processing work package for service #{wp.service} core #{core}")

    # TODO for now, we ignore core from builder and always use our assigned core
    core = NodeStateServer.instance().assigned_core()

    if NodeStateServer.instance().assigned_core() == core do
      services = get_latest_state().services

      case WorkReport.pre_execute_work_package(wp, extrinsics, core, services) do
        :error ->
          Logger.error("Failed to execute work package for service #{wp.service} core #{core}")
          {:error, :execution_failed}

        # Auth logic and import segments ok. share with other guarantors
        {import_segments, refine_task} ->
          # send WP bundle to two other guarantors in same core through CE 134
          bundle_bin = Encodable.encode(WorkPackage.bundle(wp))
          Logger.info("Work package validated successfully. Sending to other guarantors")

          validators = NodeStateServer.same_core_guarantors()

          responses =
            for v <- validators do
              case ConnectionManager.instance().get_connection(v.ed25519) do
                {:ok, pid} ->
                  dict = WorkReport.get_segment_lookup_dict(wp)

                  {v.ed25519,
                   Network.Connection.send_work_package_bundle(pid, bundle_bin, core, dict)}

                {:error, e} ->
                  Logger.warning(
                    "Could not send WP Bundle: no active connection to validator #{b16(v.ed25519)}"
                  )

                  {v.ed25519, {:error, e}}
              end
            end

          {work_report, exports} = Task.await(refine_task)

          wr_hash = h(e(work_report))

          Logger.info(
            "📦 Executed work_package=#{b16(work_report.specification.work_package_hash)}" <>
              " service=#{wp.service} core=#{core} exports_root=#{b16(work_report.specification.exports_root)}" <>
              " work_report=#{b16(wr_hash)}"
          )

          {priv, _} = KeyManager.get_our_ed25519_keypair()

          my_credential =
            {NodeStateServer.validator_index(),
             Crypto.sign(SigningContexts.jam_guarantee() <> wr_hash, priv)}

          credentials = [
            my_credential
            | for {pub_key, {:ok, {hash, signature}}} <- responses,
                  hash == wr_hash,
                  payload = SigningContexts.jam_guarantee() <> hash,
                  Crypto.valid_signature?(signature, payload, pub_key) do
                {NodeStateServer.validator_index(pub_key), signature}
              end
          ]

          if length(credentials) == 1 do
            Logger.warning("No other guarantor confirmed work report")
          else
            guarantee = %Guarantee{
              work_report: work_report,
              timeslot: NodeStateServer.current_timeslot(),
              credentials: credentials
            }

            Storage.put(guarantee)

            # send guarantee to all validators
            for {_, pid} <- ConnectionManager.instance().get_connections() do
              Network.Connection.distribute_guarantee(pid, guarantee)
            end
          end

          # stores segment root for later retrieval
          root = MerkleTree.merkle_root(exports)

          Storage.put_segments_root(work_report.specification.work_package_hash, root)

          {:ok, import_segments, work_report}
          # TODO
          # erasure code exports and save for upcoming calls
          :ok
      end
    else
      {:error, :not_assigned_to_core}
    end
  end

  # CE 134 - Work-package sharing
  @impl true
  def save_work_package_bundle(bundle, core, _segment_lookup_dict) do
    Logger.info("Saving and executing work package bundle for core #{core}")

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
      for e <- wi.extrinsic, do: Storage.put(e)

      # TODO Verify and save all justifications
    end

    services = get_latest_state().services

    case WorkReport.pre_execute_work_package(
           bundle.work_package,
           bundle.extrinsics,
           core,
           services
         ) do
      :error ->
        Logger.error(
          "Failed to execute work package for service #{bundle.work_package.service} core #{core}"
        )

        {:error, :execution_failed}

      {_, refine_task} ->
        # Execute refine, calculate wp hash and returns signature if sucessful
        {work_report, _exports} = Task.await(refine_task)
        wr_hash = h(e(work_report))

        Logger.info(
          "📦 Other guarantor work_package=#{b16(work_report.specification.work_package_hash)}" <>
            " service=#{bundle.work_package.service} core=#{core} exports_root=#{b16(work_report.specification.exports_root)}" <>
            " work_report=#{b16(wr_hash)}"
        )

        {priv, _} = KeyManager.get_our_ed25519_keypair()
        signature = Crypto.sign(SigningContexts.jam_guarantee() <> wr_hash, priv)
        {:ok, {wr_hash, signature}}
    end
  end

  # CE 144 - Audit announcement
  @impl true
  def save_audit(_audit) do
    {:error, :not_implemented}
  end

  # CE 137 - Work Package Shard Request
  @impl true
  def get_work_package_shard(_erasure_root, _shard_index) do
    {:error, :not_implemented}
  end

  # CE 139/140: Segment shard request
  @impl true
  def get_segment_shards(_erasure_root, _shard_index, _segment_indexes) do
    {:error, :not_implemented}
  end

  # CE 129 - State request
  @impl true
  def get_state_trie(header_hash) do
    case Storage.get_state_trie(header_hash) do
      nil -> {:error, :no_state}
      trie -> {:ok, trie}
    end
  end

  @impl true
  def get_justification(_erasure_root, _segment_index, _shard_index) do
    {:error, :not_implemented}
  end
end
