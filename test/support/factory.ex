# test/support/factory.ex
defmodule Jamixir.Factory do
  alias RingVRF.RingCommitment
  alias Block.Extrinsic.Preimage
  alias System.State.CoreReports
  use ExMachina

  alias Block.Extrinsic.Guarantee.{WorkResult, WorkReport}
  alias Block.{Header, Extrinsic}
  alias Block.Extrinsic.{Guarantee, Disputes}
  alias System.State.SealKeyTicket

  @cores 2
  @validator_count 6
  @epoch_length 600
  @max_authorizers_per_core 2
  @max_authorize_queue_items 4

  # Validator Key Pairs Factory
  def validator_and_key_pairs_factory(count \\ @validator_count) do
    {validators, key_pairs} =
      Enum.map(1..count, fn _ ->
        keypair = RingVrf.generate_secret_from_rand()

        {build(:validator, bandersnatch: elem(keypair, 1)), keypair}
      end)
      |> Enum.unzip()

    %{validators: validators, key_pairs: key_pairs}
  end

  # Seal Key Ticket Factory

  @spec single_seal_key_ticket_factory(list(), any(), integer()) :: System.State.SealKeyTicket.t()
  def single_seal_key_ticket_factory(key_pairs, entropy_pool_history, i) do
    {secret, _} = Enum.at(key_pairs, rem(i, length(key_pairs)))

    entry_index = Enum.random([0, 1])

    context =
      SigningContexts.jam_ticket_seal() <>
        Enum.at(entropy_pool_history, 2) <>
        <<entry_index::8>>

    %SealKeyTicket{
      id: RingVrf.ietf_vrf_output(secret, context),
      entry_index: entry_index
    }
  end

  def seal_key_ticket_factory(key_pairs, entropy_pool_history) do
    Enum.map(0..(@epoch_length - 1), fn i ->
      single_seal_key_ticket_factory(key_pairs, entropy_pool_history, i)
    end)
  end

  def genesis_state_factory do
    %{state: state} =
      build(:genesis_state_with_safrole)

    state
  end

  def genesis_state_with_safrole_factory(attrs) do
    validator_count = Map.get(attrs, :validator_count, @validator_count)

    %{validators: validators, key_pairs: key_pairs} =
      validator_and_key_pairs_factory(validator_count)

    public_keys = Enum.map(key_pairs, &(&1 |> elem(1)))
    RingVrf.init_ring_context(length(validators))

    entropy_pool = build(:entropy_pool)
    tickets = seal_key_ticket_factory(key_pairs, entropy_pool.history)

    safrole_state = %System.State.Safrole{
      pending: validators,
      epoch_root: RingVrf.create_commitment(public_keys) |> RingCommitment.encode(),
      current_epoch_slot_sealers: tickets,
      ticket_accumulator: tickets
    }

    state = %System.State{
      authorizer_pool: authorizer_pool_factory(),
      safrole: safrole_state,
      services: services_factory(),
      entropy_pool: entropy_pool,
      next_validators: validators,
      curr_validators: validators,
      prev_validators: validators,
      authorizer_queue: authorizer_queue_factory(),
      validator_statistics: build(:validator_statistics)
    }

    %{state: state, validators: validators, key_pairs: key_pairs}
  end

  # Work Report and Availability Factories

  def work_report_factory do
    %WorkReport{
      specification: build(:availability),
      refinement_context: build(:refinement_context),
      core_index: 1,
      authorizer_hash: <<2::256>>,
      output: <<3>>,
      work_results: build_list(2, :work_result)
    }
  end

  def availability_factory do
    %Block.Extrinsic.Availability{
      work_package_hash: <<1::256>>,
      work_bundle_length: 2,
      erasure_root: <<3::256>>,
      segment_root: <<4::256>>
    }
  end

  def refinement_context_factory do
    %RefinementContext{
      anchor: <<1::256>>,
      posterior_state_root: <<2::256>>,
      posterior_beefy_root: <<3::256>>,
      lookup_anchor: <<4::256>>,
      timeslot: 5,
      prerequisite: <<6::256>>
    }
  end

  def work_result_factory do
    %WorkResult{
      service_index: 0,
      code_hash: <<1::256>>,
      payload_hash: <<2::256>>,
      gas_prioritization_ratio: 3,
      output_or_error: {:ok, <<4>>}
    }
  end

  def work_item_factory do
    %Block.Extrinsic.WorkItem{
      service_id: 1,
      code_hash: <<1::256>>,
      payload_blob: <<2>>,
      gas_limit: 3,
      imported_data_segments: [{<<4::256>>, 5}],
      blob_hashes_and_lengths: [{<<6::256>>, 7}],
      exported_data_segments_count: 8
    }
  end

  def work_package_factory do
    %Block.Extrinsic.WorkPackage{
      authorization_token: <<1>>,
      service_index: 2,
      authorization_code_hash: <<3>>,
      parameterization_blob: <<4>>,
      context: %RefinementContext{},
      work_items: [build(:work_item)]
    }
  end

  # Validator Factories

  def validator_factory do
    %System.State.Validator{
      bandersnatch: :crypto.strong_rand_bytes(32),
      ed25519: :crypto.strong_rand_bytes(32),
      bls: :crypto.strong_rand_bytes(144),
      metadata: :crypto.strong_rand_bytes(128)
    }
  end

  def indexed_validator_factory(index) do
    %System.State.Validator{
      bandersnatch: <<index::256>>,
      ed25519: <<index::256>>,
      bls: <<index::1152>>,
      metadata: <<index::1024>>
    }
  end

  # Ticket Factories
  def single_seal_key_ticket_factory do
    %System.State.SealKeyTicket{
      id: <<1::256>>,
      entry_index: 0
    }
  end

  def seal_key_ticket_factory do
    %System.State.SealKeyTicket{
      id: random_hash(),
      entry_index: sequence(:entry_index, fn n -> rem(n, 2) end)
    }
  end

  # Safrole Factoriy
  def safrole_factory do
    %System.State.Safrole{
      pending: build_list(@validator_count, :validator),
      # Placeholder for epoch root
      epoch_root: :crypto.strong_rand_bytes(144),
      current_epoch_slot_sealers: build_list(@epoch_length, :seal_key_ticket),
      ticket_accumulator: build_list(@epoch_length, :seal_key_ticket)
    }
  end

  # Authorizer Factories
  def authorizer_queue_factory do
    Enum.map(1..@cores, fn _ ->
      Enum.map(1..@max_authorize_queue_items, fn _ ->
        unique_hash_factory()
      end)
    end)
  end

  def authorizer_pool_factory do
    Enum.map(1..@cores, fn _ ->
      Enum.map(1..@max_authorizers_per_core, fn _ ->
        unique_hash_factory()
      end)
    end)
  end

  def unique_hash_factory do
    :crypto.strong_rand_bytes(32)
  end

  # Service Factories

  def services_factory do
    # Create a map with a single ServiceAccount
    %{1 => build(:service_account)}
  end

  def service_account_factory do
    %System.State.ServiceAccount{
      storage: %{random_hash() => <<0xDEADBEEF::32>>},
      preimage_storage_p: %{random_hash() => <<0xCAFEBABE::32>>},
      preimage_storage_l: %{{random_hash(), 0} => [1, 2, 3]},
      code_hash: <<4::256>>,
      balance: 1000,
      gas_limit_g: 5000,
      gas_limit_m: 10000
    }
  end

  # Entropy Pool Factory

  def entropy_pool_factory do
    %System.State.EntropyPool{
      current: random_hash(),
      history:
        Enum.map(1..3, fn _ ->
          unique_hash_factory()
        end)
    }
  end

  # Core Reports Factory
  def core_reports_factory do
    %CoreReports{reports: [build(:core_report), nil]}
  end

  def core_report_factory do
    %System.State.CoreReport{
      work_report: build(:work_report),
      timeslot: sequence(:core_report_timeslot, & &1)
    }
  end

  def privileged_services_factory do
    %System.State.PrivilegedServices{
      manager_service: sequence(:manager_service, & &1),
      alter_authorizer_service: sequence(:alter_authorizer_service, & &1),
      alter_validator_service: sequence(:alter_validator_service, & &1)
    }
  end

  # Judgements Factory
  def judgements_factory do
    %System.State.Judgements{
      good: [random_hash()],
      bad: [random_hash()],
      wonky: [random_hash()],
      punish: [random_hash()]
    }
  end

  # Validator Statistics Factory
  def validator_statistics_factory(attrs) do
    count = Map.get(attrs, :count, @validator_count)

    %System.State.ValidatorStatistics{
      current_epoch_statistics: build_list(count, :statistics),
      previous_epoch_statistics: build_list(count, :statistics)
    }
  end

  def statistics_factory do
    %System.State.ValidatorStatistic{
      availability_assurances: 6
    }
  end

  def block_factory do
    %Block{
      extrinsic: build(:extrinsic),
      header: build(:header)
    }
  end

  def safrole_block_factory(attrs) do
    state = Map.get(attrs, :state)
    key_pairs = Map.get(attrs, :key_pairs)
    timeslot = Map.get(attrs, :timeslot, 1)

    block_author_key_index = rem(timeslot, length(state.safrole.current_epoch_slot_sealers))
    block_author_key_pair = Enum.at(key_pairs, block_author_key_index)

    # Build and seal the header dynamically with the correct timeslot
    header =
      System.HeaderSeal.seal_header(
        build(:header, timeslot: timeslot, block_author_key_index: block_author_key_index),
        state.safrole.current_epoch_slot_sealers,
        state.entropy_pool,
        block_author_key_pair
      )

    %Block{
      extrinsic: build(:extrinsic),
      header: header
    }
  end

  def extrinsic_factory do
    %Extrinsic{
      tickets: [%SealKeyTicket{}],
      disputes: %Disputes{},
      preimages: build_list(2, :preimage),
      assurances: [%Assurance{}],
      guarantees: [build(:guarantee)]
    }
  end

  def header_factory do
    %Header{
      timeslot: 5,
      parent_hash: random_hash(),
      prior_state_root: random_hash(),
      epoch: 0,
      # Hw
      winning_tickets_marker: [],
      # Hj
      judgements_marker: [random_hash()],
      # Ho
      offenders_marker: [random_hash()],
      # Hi
      block_author_key_index: 0,
      # Hv
      vrf_signature: <<>>,
      # Hs
      block_seal: <<>>
    }
  end

  def guarantee_factory do
    %Guarantee{
      work_report: build(:work_report),
      timeslot: 5,
      credential: [{1, random_hash()}]
    }
  end

  def preimage_factory do
    id = sequence(:preimage, & &1)
    %Preimage{service_index: id, data: <<1, 2, 3, 4, id>>}
  end

  def assurance_factory do
    %Assurance{
      hash: random_hash(),
      assurance_values: <<1, 0, 1>>,
      validator_index: 1,
      signature: <<123, 45, 67>>
    }
  end

  def shuffle_hash_factory do
    Util.Hash.blake2b_256(<<"This generates the shuffle hash for testing">>)
  end

  # Private Helper Functions
  defp random_hash do
    :crypto.strong_rand_bytes(32)
  end
end
