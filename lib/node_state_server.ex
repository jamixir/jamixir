defmodule Jamixir.NodeStateServerBehaviour do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.Validator
  @callback current_connections() :: list()
  @callback assigned_shard_index(non_neg_integer(), binary()) :: non_neg_integer() | nil
  @callback assigned_shard_index(binary()) :: non_neg_integer() | nil
  @callback neighbours() :: list(Validator.t())
  @callback validator_index() :: non_neg_integer()
  @callback fetch_work_report_shards(pid(), WorkReport.t()) :: :ok
end

defmodule Jamixir.NodeStateServer do
  @behaviour Jamixir.NodeStateServerBehaviour

  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.{Assurance, Guarantee, Guarantee.WorkReport}
  alias Block.Extrinsic.{GuarantorAssignments, TicketProof}
  alias Block.Header
  alias Block
  alias Jamixir.Genesis
  alias Network.{Connection, ConnectionManager}
  alias System.State
  alias System.State.{CoreReport, EntropyPool, RotateKeys, Validator}
  alias Util.Logger, as: Log
  import Util.Hex, only: [b16: 1]
  import Codec.Encoder
  use GenServer

  def instance do
    Application.get_env(:jamixir, :node_state_server, Jamixir.NodeStateServer)
  end

  defstruct [
    :jam_state,
    :bandersnatch_keypair
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    bandersnatch_keypair = KeyManager.get_our_bandersnatch_keypair()
    Process.send_after(self(), {:check_jam_state, opts[:jam_state]}, 0)
    {:ok, %__MODULE__{jam_state: opts[:jam_state], bandersnatch_keypair: bandersnatch_keypair}}
  end

  # ============================================================================
  # SYNCHRONOUS API - State Query Functions
  # ============================================================================

  # Core state access
  def get_jam_state, do: GenServer.call(__MODULE__, :get_jam_state)
  def current_timeslot, do: GenServer.call(__MODULE__, :current_timeslot)

  # Block operations
  def add_block(block, false), do: GenServer.call(__MODULE__, {:add_block, block, false})
  def add_block(block), do: GenServer.call(__MODULE__, {:add_block, block, true})

  # Validator and network information
  def validator_index(ed25519_pubkey) when is_binary(ed25519_pubkey) do
    GenServer.call(__MODULE__, {:validator_index, ed25519_pubkey})
  end

  @impl true
  def validator_index,
    do: GenServer.call(__MODULE__, {:validator_index, KeyManager.get_our_ed25519_key()})

  @impl true
  def current_connections, do: GenServer.call(__MODULE__, :current_connections)

  @impl true
  def neighbours(), do: GenServer.call(__MODULE__, :neighbours)

  # Guarantor and core assignment functions
  def guarantors, do: GenServer.call(__MODULE__, :guarantors)

  def same_core_guarantors, do: GenServer.call(__MODULE__, :same_core_guarantors)

  @impl true
  def assigned_shard_index(core, key \\ KeyManager.get_our_ed25519_key()) do
    GenServer.call(__MODULE__, {:assigned_shard_index, core, key})
  end

  def assigned_core, do: GenServer.call(__MODULE__, :assigned_core)

  # ============================================================================
  # ASYNCHRONOUS API
  # ============================================================================

  def set_jam_state(state), do: GenServer.cast(__MODULE__, {:set_jam_state, state})

  @impl true
  def fetch_work_report_shards(guarantor_pid, spec),
    do: GenServer.cast(__MODULE__, {:fetch_work_report_shards, guarantor_pid, spec})

  # ============================================================================
  # GENSERVER HANDLERS - Synchronous Calls
  # ============================================================================

  # Core state access handlers
  @impl true
  def handle_call(:get_jam_state, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, jam_state, state}
  end

  @impl true
  def handle_call(:current_timeslot, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, jam_state.timeslot, state}
  end

  # Block operation handlers
  @impl true
  def handle_call(
        {:add_block, block, announce},
        _from,
        %__MODULE__{jam_state: jam_state} = state
      ) do
    new_jam_state =
      case Jamixir.Node.add_block(block, jam_state) do
        {:ok, %State{} = new_jam_state, state_root} ->
          header_hash = h(e(block.header))

          Log.info(
            "🔄 State Updated successfully. H: #{b16(header_hash)} root: #{b16(state_root)}"
          )

          #  Notify Subscription Manager, which will notify "bestBlock" subscribers
          Phoenix.PubSub.broadcast(Jamixir.PubSub, "node_events", {:new_block, block})

          # Telemetry: best block changed
          Jamixir.Telemetry.best_block_changed(block.header.timeslot, header_hash)

          if announce, do: announce_block_to_peers(block)
          new_jam_state

        {:error, _, reason} ->
          Log.block(:error, "Failed to add block: #{reason}")
          jam_state
      end

    genServerState = %__MODULE__{state | jam_state: new_jam_state}

    {:reply, {:ok, new_jam_state}, genServerState}
  end

  # Validator and network information handlers
  @impl true
  def handle_call({:validator_index, ed25519_key}, _from, %__MODULE__{jam_state: jam_state} = s) do
    {:reply, find_validator_index(ed25519_key, jam_state.curr_validators), s}
  end

  @impl true
  def handle_call(:current_connections, _from, %__MODULE__{jam_state: jam_state} = s) do
    {:reply, connections(jam_state.curr_validators), s}
  end

  def handle_call(:neighbours, _from, %__MODULE__{jam_state: jam_state} = s) do
    me = KeyManager.our_validator()

    neighbours =
      Validator.neighbours(
        me,
        jam_state.prev_validators,
        jam_state.curr_validators,
        jam_state.next_validators
      )

    {:reply, neighbours, s}
  end

  # Guarantor and core assignment handlers
  @impl true
  def handle_call(:guarantors, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, guarantors(jam_state), state}
  end

  @impl true
  def handle_call(:same_core_guarantors, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, same_core_guarantors(jam_state), state}
  end

  @impl true
  def handle_call(
        {:assigned_shard_index, core, key},
        _from,
        %__MODULE__{jam_state: jam_state} = state
      ) do
    {:reply, calculate_assigned_shard_index(core, key, jam_state.curr_validators), state}
  end

  @impl true
  def handle_call(:assigned_core, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, assigned_core(jam_state), state}
  end

  # ============================================================================
  # GENSERVER HANDLERS - Asynchronous Casts
  # ============================================================================

  @impl true
  def handle_cast({:set_jam_state, jam_state}, state) do
    Log.info("Setting JAM state in NodeStateServer")
    {:noreply, %{state | jam_state: jam_state}}
  end

  def handle_cast(
        {:fetch_work_report_shards, guarantor_pid, work_report},
        %__MODULE__{jam_state: jam_state} = state
      ) do
    spec = work_report.specification

    shard_index =
      find_validator_index(KeyManager.get_our_ed25519_key(), jam_state.curr_validators)

    case Network.Connection.request_work_package_shard(
           guarantor_pid,
           spec.erasure_root,
           shard_index
         ) do
      {:ok, {_bundle_shard, segments_shards, _justifications}} ->
        Log.debug("Received EC shard for work package: #{b16(spec.work_package_hash)}")

        for {segment_shard, segment_index} <- Enum.with_index(segments_shards) do
          Storage.put_segment_shard(spec.erasure_root, shard_index, segment_index, segment_shard)
        end

        {_, header} = Storage.get_latest_header()
        hash = h(e(header))

        updated_assurance =
          case Storage.get_assurance(hash, shard_index) do
            nil ->
              bitfield = Utils.set_bit(<<0::m(bitfield)>>, assigned_core(jam_state))

              %Assurance{
                hash: hash,
                validator_index: shard_index,
                bitfield: bitfield
              }

            assurance ->
              %Assurance{
                assurance
                | bitfield: Utils.set_bit(assurance.bitfield, assigned_core(jam_state))
              }
          end

        {priv, _} = KeyManager.get_our_ed25519_keypair()
        Storage.put(Assurance.signed(updated_assurance, priv))

      {:error, reason} ->
        Log.error(
          "Failed to retrieve EC for work report #{b16(spec.work_package_hash)}: #{inspect(reason)}"
        )
    end

    {:noreply, state}
  end

  # ============================================================================
  # GENSERVER HANDLERS - Info Messages (Clock Events & Initialization)
  # ============================================================================

  @impl true
  def handle_info(
        {:check_jam_state, s},
        %__MODULE__{jam_state: nil} = state
      ) do
    case s || Storage.get_state(Genesis.genesis_header_hash()) do
      nil ->
        # Still not available, check again later
        Process.send_after(self(), {:check_jam_state, nil}, 100)
        {:noreply, state}

      jam_state ->
        Log.info("📨 NodeStateServer received JAM state")
        Phoenix.PubSub.subscribe(Jamixir.PubSub, "node_events")

        {:noreply, %__MODULE__{state | jam_state: jam_state}}
    end
  end

  # Already have JAM state, ignore
  @impl true
  def handle_info({:check_jam_state, _}, state), do: {:noreply, state}

  @impl true
  def handle_info(
        {:clock, %{event: :compute_author_slots, slot: slot}},
        %__MODULE__{jam_state: jam_state, bandersnatch_keypair: bandersnatch_keypair} = state
      ) do
    current_epoch = Util.Time.epoch_index(slot)
    next_epoch = current_epoch + 1

    Log.debug("⚙️ Computing authoring slots for next epoch #{next_epoch} at slot #{slot}")

    authoring_slots =
      compute_author_slots_for_epoch(jam_state, next_epoch, bandersnatch_keypair)

    Clock.set_authoring_slots(authoring_slots)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:clock, %{event: :compute_current_epoch_author_slots, slot: slot}},
        %__MODULE__{jam_state: jam_state, bandersnatch_keypair: bandersnatch_keypair} = state
      ) do
    Log.debug("⚙️ Computing authoring slots for current epoch at slot #{slot}")
    current_epoch = Util.Time.epoch_index(slot)

    authoring_slots =
      compute_author_slots_for_epoch(jam_state, current_epoch, bandersnatch_keypair)

    Clock.set_authoring_slots(authoring_slots)

    {:noreply, state}
  end

  def handle_info(
        {:clock, %{event: :assurance_timeout, slot: slot}},
        %{jam_state: jam_state} = state
      ) do
    Log.info("⏰ Assurance timeout event for slot #{slot}")
    {_, header} = Storage.get_latest_header()
    hash = h(e(header))
    my_index = find_validator_index(KeyManager.get_our_ed25519_key(), jam_state.curr_validators)

    case Storage.get_assurance(hash, my_index) do
      nil ->
        Log.debug("No assurance found for parent block #{b16(hash)}")

      assurance ->
        Log.info("🛡️ Distributing assurance for parent block #{b16(hash)}")

        for {_, pid} <- ConnectionManager.instance().get_connections() do
          Task.start(fn ->
            Connection.distribute_assurance(pid, assurance)
          end)
        end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:clock, %{event: :author_block, slot: slot, epoch: epoch, epoch_phase: epoch_phase}},
        %__MODULE__{jam_state: jam_state} = state
      ) do
    Log.info("📨 author_block event for slot #{slot} (epoch #{epoch}, phase #{epoch_phase})")

    {_, parent_header} = Storage.get_latest_header()
    parent_hash = h(e(parent_header))

    # Telemetry: authoring event
    authoring_event_id = Jamixir.Telemetry.authoring(slot, parent_hash)

    # Tickets selection
    existing_tickets = Storage.get_tickets(epoch)
    Log.debug("Existing tickets for epoch #{epoch}: #{length(existing_tickets)}")
    tickets = TicketProof.tickets_for_new_block(existing_tickets, jam_state, epoch_phase)

    # Assurances selection
    # Formula (11.11) v0.7.2
    existing_assurances = Storage.get_assurances(parent_hash)

    #  Simulate ρ‡ (partial state transform)

    # ρ† Formula (4.12) - process disputes
    # TODO:  pass actual bad_wonky_verdicts here
    bad_wonky_verdicts = []
    core_reports_1 = CoreReport.process_disputes(jam_state.core_reports, bad_wonky_verdicts)

    # R Formula (11.16) - compute which work-reports become available
    available_work_reports = WorkReport.available_work_reports(assurances, core_reports_1)

    # ρ‡ Formula (4.13) - clear available and timed-out reports
    core_reports_2 =
      CoreReport.process_availability(
        jam_state.core_reports,
        core_reports_1,
        available_work_reports,
        slot
      )

    guarantee_candidates = Storage.get_guarantees(:pending)
    Log.debug("Guarantee candidates for block inclusion: #{length(guarantee_candidates)}")

    Log.info("🧩 Guarantee candidates: #{length(guarantee_candidates)}")
    latest_state_root = Storage.get_latest_state_root()

    # Note: this may filter some guarantees out, in that case the core_index will have no guarantee assigned.
    # There is no attempt to "re-fetch" new candidates from storage for such core indices.
    # This is inline with Formula 11.24, but in case a node gets compensation for inclusion of more guarantees, we may want to be more aggressive
    # and try to fully populate the extrinsic.
    guarantees_to_include =
      Guarantee.guarantees_for_new_block(
        guarantee_candidates,
        jam_state,
        slot,
        latest_state_root,
        core_reports_2
      )

    preimage_candidates = Storage.get_preimages(:pending)
    Log.debug("Preimage candidates for block inclusion: #{length(preimage_candidates)}")

    preimages_to_include =
      Preimage.preimages_for_new_block(preimage_candidates, jam_state.services)

    # =======================================================
    # Create block
    # =======================================================

    Log.info(
      "New block with #{length(tickets)} 🎟️ tickets, " <>
        "#{length(assurances)} 🛡️ assurances, " <>
        "#{length(guarantees_to_include)} 🧩 guarantees, " <>
        "#{length(preimages_to_include)} 🖼️ preimages"
    )

    extrinsics = %Block.Extrinsic{
      tickets: tickets,
      assurances: assurances,
      guarantees: guarantees_to_include,
      preimages: preimages_to_include
    }

    case Block.new(extrinsics, parent_hash, jam_state, slot) do
      {:ok, block} ->
        header_hash = h(e(block.header))
        Log.block(:info, "⛓️ Block created successfully. Header Hash #{b16(header_hash)}")
        Log.block(:debug, "⛓️ Block created successfully. #{inspect(block)}")

        # Telemetry: authored event
        Jamixir.Telemetry.authored(authoring_event_id, block)

        Task.start(fn -> add_block(block) end)

      {:error, reason} ->
        Log.consensus(:debug, "Failed to create block: #{reason}")
        # Telemetry: authoring failed
        Jamixir.Telemetry.authoring_failed(authoring_event_id, to_string(reason))
    end

    {:noreply, state}
  end

  def handle_info({:clock, :telemetry_status}, state) do
    Jamixir.Telemetry.status(%{
      peer_count: map_size(ConnectionManager.get_connections()),
      validator_count: Constants.validator_count(),
      announcement_streams_count: 0,
      guarantees_in_pool: [0, 0],
      shards_count: 0,
      shards_total_size: 0,
      preimages_count: 0,
      preimages_total_size: 0
    })

    {:noreply, state}
  end

  def handle_info(
        {:clock, %{event: {:produce_new_tickets, target_epoch}}},
        %__MODULE__{jam_state: jam_state} = state
      ) do
    Log.info("🌕 Time to produce new tickets for epoch #{target_epoch}")

    # Telemetry: generating tickets event
    generating_event_id = Jamixir.Telemetry.generating_tickets(target_epoch)

    my_index = find_validator_index(KeyManager.get_our_ed25519_key(), jam_state.curr_validators)

    tickets =
      TicketProof.create_new_epoch_tickets(
        jam_state,
        KeyManager.get_our_bandersnatch_keypair(),
        my_index
      )

    ticket_outputs =
      for ticket <- tickets do
        output =
          case TicketProof.proof_output(
                 ticket,
                 jam_state.entropy_pool.n1,
                 jam_state.safrole.epoch_root
               ) do
            {:ok, <<output::256>>} ->
              output

            {:error, :verification_failed} ->
              Log.warning("Ticket proof verification fail. Probably invalid state commitment.")
              0
          end

        proxy_index = rem(output, Constants.validator_count())
        key = Enum.at(jam_state.curr_validators, proxy_index).ed25519
        proxy_connection = ConnectionManager.instance().get_connection(key)

        if key == KeyManager.get_our_ed25519_key() or elem(proxy_connection, 0) == :error do
          Log.info("No proxy found, so sending ticket directly")

          for {_, pid} <- ConnectionManager.instance().get_connections() do
            Task.start(fn ->
              Log.info("🎟️ Sending ticket to validator")
              Network.Connection.distribute_ticket(pid, :validator, target_epoch, ticket)
            end)
          end
        else
          {:ok, pid} = proxy_connection
          Log.info("🎟️ Sending ticket to proxy #{proxy_index}")
          Network.Connection.distribute_ticket(pid, :proxy, target_epoch, ticket)
        end

        <<output::256>>
      end

    Jamixir.Telemetry.tickets_generated(generating_event_id, ticket_outputs)

    {:noreply, state}
  end

  def handle_info({:new_block, %Block{extrinsic: extrinsic} = block}, state) do
    # mark its guarantees as included
    if length(extrinsic.guarantees) > 0 do
      guarantee_work_report_hashes =
        Enum.map(extrinsic.guarantees, &h(e(&1.work_report)))

      header_hash = h(e(block.header))
      Storage.mark_guarantee_included(guarantee_work_report_hashes, header_hash)
    end

    # Mark included preimages
    for preimage <- extrinsic.preimages do
      preimage_hash = h(e(preimage))
      Storage.mark_preimage_included(preimage_hash, preimage.service)
    end

    {:noreply, state}
  end

  def handle_info(_event, state), do: {:noreply, state}

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS
  # ============================================================================

  # Validator and index utilities
  defp find_validator_index(ed25519_pubkey, validators),
    do: Enum.find_index(validators, &(&1.ed25519 == ed25519_pubkey))

  # Assigned shard index calculation: i = (cR + v) mod V
  defp calculate_assigned_shard_index(core, key, validators) do
    case find_validator_index(key, validators) do
      nil ->
        nil

      v ->
        rem(core * Constants.erasure_code_recovery_threshold() + v, Constants.validator_count())
    end
  end

  # Core assignment helpers
  defp assigned_core(%GuarantorAssignments{} = guarantors) do
    index =
      Enum.find_index(guarantors.validators, fn v ->
        v.ed25519 == KeyManager.get_our_ed25519_key()
      end)

    if index, do: guarantors.assigned_cores |> Enum.at(index), else: nil
  end

  defp assigned_core(%State{} = jam_state), do: assigned_core(guarantors(jam_state))

  defp same_core_guarantors(%State{} = jam_state) do
    guarantors_data = guarantors(jam_state)

    case assigned_core(guarantors_data) do
      nil ->
        []

      core ->
        Enum.zip(guarantors_data.validators, guarantors_data.assigned_cores)
        |> Enum.filter(fn {v, c} ->
          v.ed25519 != KeyManager.get_our_ed25519_key() and c == core
        end)
        |> Enum.map(fn {v, _c} -> v end)
    end
  end

  defp guarantors(%State{} = jam_state) do
    GuarantorAssignments.guarantors(
      jam_state.entropy_pool.n2,
      jam_state.timeslot,
      jam_state.curr_validators,
      MapSet.new()
    )
  end

  # Network and connection helpers
  defp connections(validators) do
    for v <- validators, do: {v, ConnectionManager.get_connection(v.ed25519)}
  end

  defp announce_block_to_peers(block) do
    client_pids = ConnectionManager.get_connections()
    Log.debug("📢 Announcing block to #{map_size(client_pids)} peers")

    header_hash = h(e(block.header))

    for {ed25519_key, pid} <- client_pids do
      Connection.announce_block(pid, block.header, block.header.timeslot)
      # Telemetry: block announced (we are the announcer)
      Jamixir.Telemetry.block_announced(ed25519_key, :local, block.header.timeslot, header_hash)
    end
  end

  # Authoring and slot computation
  defp compute_author_slots_for_epoch(jam_state, epoch, bandersnatch_keypair) do
    epoch_first_slot = epoch * Constants.epoch_length()

    header = %Header{timeslot: epoch_first_slot}

    entropy_pool_ =
      EntropyPool.rotate(epoch_first_slot, jam_state.timeslot, jam_state.entropy_pool)

    {_pending_, curr_validators_, _prev_validators_, _epoch_root_} =
      RotateKeys.rotate_keys(header, jam_state, %System.State.Judgements{})

    next_epoch_slot_sealers =
      System.State.Safrole.get_epoch_slot_sealers_(
        header,
        jam_state.timeslot,
        jam_state.safrole,
        entropy_pool_,
        curr_validators_
      )

    authoring_slots =
      0..(Constants.epoch_length() - 1)
      |> Enum.filter(fn phase ->
        slot_sealer = Enum.at(next_epoch_slot_sealers, phase)
        Block.key_matches?(bandersnatch_keypair, slot_sealer, entropy_pool_)
      end)
      |> Enum.map(fn phase -> {epoch, phase} end)
      |> MapSet.new()

    Log.info("✏️ We are assigned to author #{inspect(authoring_slots)} slots in epoch #{epoch}")

    authoring_slots
  end
end
