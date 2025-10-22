defmodule Jamixir.NodeStateServerBehaviour do
  @callback current_connections() :: list()
  @callback assigned_shard_index(non_neg_integer(), binary()) :: non_neg_integer() | nil
  @callback assigned_shard_index(binary()) :: non_neg_integer() | nil
  @callback neighbours() :: list(Validator.t())
end

defmodule Jamixir.NodeStateServer do
  @behaviour Jamixir.NodeStateServerBehaviour

  alias System.State.SealKeyTicket
  alias Block.Extrinsic.TicketProof
  alias System.State.Validator
  alias System.State.RotateKeys
  alias System.State.EntropyPool
  alias Block.Header
  alias Block.Extrinsic.GuarantorAssignments
  alias Jamixir.Genesis
  alias Network.{Connection, ConnectionManager}
  alias System.State
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

  def add_block(block, false), do: GenServer.call(__MODULE__, {:add_block, block, false})
  def add_block(block), do: GenServer.call(__MODULE__, {:add_block, block, true})
  def inspect_state(header_hash), do: GenServer.call(__MODULE__, {:inspect_state, header_hash})

  def inspect_state(header_hash, key),
    do: GenServer.call(__MODULE__, {:inspect_state, header_hash, key})

  def load_state(path), do: GenServer.call(__MODULE__, {:load_state, path})
  @impl true
  def current_connections, do: GenServer.call(__MODULE__, :current_connections)

  @impl true
  def neighbours(), do: GenServer.call(__MODULE__, :neighbours)

  def validator_index(ed25519_pubkey) when is_binary(ed25519_pubkey) do
    GenServer.call(__MODULE__, {:validator_index, ed25519_pubkey})
  end

  def validator_index(validators) when is_list(validators) do
    validator_index(KeyManager.get_our_ed25519_key(), validators)
  end

  def validator_index, do: validator_index(KeyManager.get_our_ed25519_key())

  def validator_index(ed25519_pubkey, validators),
    do: Enum.find_index(validators, &(&1.ed25519 == ed25519_pubkey))

  def current_timeslot do
    GenServer.call(__MODULE__, :current_timeslot)
  end

  def guarantors, do: GenServer.call(__MODULE__, :guarantors)

  def assigned_core do
    guarantors = guarantors()

    index =
      Enum.find_index(guarantors.validators, fn v ->
        v.ed25519 == KeyManager.get_our_ed25519_key()
      end)

    if index, do: guarantors.assigned_cores |> Enum.at(index), else: nil
  end

  def same_core_guarantors do
    case assigned_core() do
      nil ->
        []

      core ->
        # we know this is calling twice the guarantors function
        # This can be improved later
        guarantors = guarantors()

        Enum.zip(guarantors.validators, guarantors.assigned_cores)
        |> Enum.filter(fn {v, c} ->
          v.ed25519 != KeyManager.get_our_ed25519_key() and c == core
        end)
        |> Enum.map(fn {v, _c} -> v end)
    end
  end

  def set_jam_state(state), do: GenServer.cast(__MODULE__, {:set_jam_state, state})
  def get_jam_state, do: GenServer.call(__MODULE__, :get_jam_state)

  @impl true
  def init(opts) do
    bandersnatch_keypair = KeyManager.get_our_bandersnatch_keypair()
    Process.send_after(self(), {:check_jam_state, opts[:jam_state]}, 0)
    {:ok, %__MODULE__{jam_state: opts[:jam_state], bandersnatch_keypair: bandersnatch_keypair}}
  end

  def connections(validators) do
    for v <- validators, do: {v, ConnectionManager.get_connection(v.ed25519)}
  end

  # Wait for initialization to complete and get jam_state
  @impl true
  def handle_call(
        {:add_block, block, announce},
        _from,
        %__MODULE__{jam_state: jam_state} = state
      ) do
    new_jam_state =
      case Jamixir.Node.add_block(block, jam_state) do
        {:ok, %State{} = new_jam_state, state_root} ->
          Log.info("🔄 State Updated successfully: #{b16(state_root)}")
          #  Notify Subscription Manager, which will notify "bestBlock" subscribers
          Phoenix.PubSub.broadcast(Jamixir.PubSub, "node_events", {:new_block, block.header})
          if announce, do: announce_block_to_peers(block)
          new_jam_state

        {:error, _, reason} ->
          Log.block(:error, "Failed to add block: #{reason}")
          jam_state
      end

    genServerState = %__MODULE__{state | jam_state: new_jam_state}

    {:reply, {:ok, new_jam_state}, genServerState}
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

  @impl true
  def handle_call({:validator_index, ed25519_key}, _from, %__MODULE__{jam_state: jam_state} = s) do
    {:reply, validator_index(ed25519_key, jam_state.curr_validators), s}
  end

  @impl true
  def handle_call(:current_timeslot, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, jam_state.timeslot, state}
  end

  @impl true
  def handle_call(:guarantors, _from, %__MODULE__{jam_state: jam_state} = state) do
    guarantors =
      GuarantorAssignments.guarantors(
        jam_state.entropy_pool.n2,
        jam_state.timeslot,
        jam_state.curr_validators,
        MapSet.new()
      )

    {:reply, guarantors, state}
  end

  @impl true
  def handle_call(:get_jam_state, _from, %__MODULE__{jam_state: jam_state} = state) do
    {:reply, jam_state, state}
  end

  @impl true
  def handle_cast({:set_jam_state, jam_state}, state) do
    Log.info("Setting JAM state in NodeStateServer")
    {:noreply, %{state | jam_state: jam_state}}
  end

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
      compute_author_slots_for_next_epoch(jam_state, slot, bandersnatch_keypair)

    Clock.set_authoring_slots(authoring_slots)

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

    existing_tickets = Storage.get_tickets(epoch)

    Log.info("Existing tickets for epoch #{epoch}: #{length(existing_tickets)}")

    entropy = jam_state.entropy_pool.n2

    tickets_and_ids =
      for ticket <- existing_tickets,
          epoch_phase != 0,
          proof = TicketProof.proof_output(ticket, entropy, jam_state.safrole.epoch_root),
          elem(proof, 0) == :ok,
          {:ok, id} = proof,
          seal = %SealKeyTicket{id: id, attempt: ticket.attempt},
          not Enum.member?(jam_state.safrole.ticket_accumulator, seal) do
        {ticket, id}
      end
      |> Enum.take(Constants.max_tickets_pre_extrinsic())
      |> Enum.sort_by(fn {_ticket, id} -> id end)

    tickets = for {ticket, _id} <- tickets_and_ids, do: ticket
    Log.info("Creating block with #{length(tickets)} 🎟️ tickets")

    case Block.new(%Block.Extrinsic{tickets: tickets}, parent_hash, jam_state, slot) do
      {:ok, block} ->
        header_hash = h(e(block.header))
        Log.block(:info, "⛓️ Block created successfully. Header Hash #{b16(header_hash)}")
        Log.block(:debug, "⛓️ Block created successfully. #{inspect(block)}")
        Task.start(fn -> add_block(block) end)

      {:error, reason} ->
        Log.consensus(:debug, "Failed to create block: #{reason}")
    end

    {:noreply, state}
  end

  def handle_info(
        {:clock, %{event: {:produce_new_tickets, target_epoch}}},
        %__MODULE__{jam_state: jam_state} = state
      ) do
    Log.info("🌕 Time to produce new tickets for epoch #{target_epoch}")
    my_index = validator_index(jam_state.curr_validators)

    tickets =
      TicketProof.create_new_epoch_tickets(
        jam_state,
        KeyManager.get_our_bandersnatch_keypair(),
        my_index
      )

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
            Log.error("How did our own ticket proof verification fail?")
            Log.error("Ticket: #{inspect(ticket)}")

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
    end

    {:noreply, state}
  end

  def handle_info(_event, state), do: {:noreply, state}

  @impl true
  # i = (cR + v) mod V
  def assigned_shard_index(core, key \\ KeyManager.get_our_ed25519_key()) do
    case validator_index(key) do
      nil ->
        nil

      v ->
        rem(core * Constants.erasure_code_recovery_threshold() + v, Constants.validator_count())
    end
  end

  defp announce_block_to_peers(block) do
    client_pids = ConnectionManager.get_connections()
    Log.debug("📢 Announcing block to #{map_size(client_pids)} peers")

    for {_address, pid} <- client_pids do
      Connection.announce_block(pid, block.header, block.header.timeslot)
    end
  end

  defp compute_author_slots_for_next_epoch(jam_state, current_slot, bandersnatch_keypair) do
    current_epoch = Util.Time.epoch_index(current_slot)
    next_epoch = current_epoch + 1
    next_epoch_first_slot = next_epoch * Constants.epoch_length()

    header = %Header{timeslot: next_epoch_first_slot}

    entropy_pool_ =
      EntropyPool.rotate(next_epoch_first_slot, jam_state.timeslot, jam_state.entropy_pool)

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
      |> Enum.map(fn phase -> {next_epoch, phase} end)
      |> MapSet.new()

    Log.info(
      "✏️ We are assigned to author #{inspect(authoring_slots)} slots in epoch #{next_epoch}"
    )

    authoring_slots
  end
end
