# test/support/factory.ex
defmodule Jamixir.Factory do
  alias Encodable.System.State.RecentHistory
  alias Block.Extrinsic.Guarantee.{WorkReport, WorkDigest}
  alias Block.Extrinsic.{Assurance, Disputes, Guarantee, TicketProof}
  alias Block.Extrinsic.Preimage
  alias Block.{Extrinsic, Header}
  alias System.HeaderSeal
  alias System.State.{RecentHistory.RecentBlock, SealKeyTicket}
  alias Util.{Crypto, Hash, Time}
  use ExMachina
  use Sizes

  @cores Constants.core_count()
  @validator_count Constants.validator_count()
  @max_authorizers_per_core 2
  @max_authorize_queue_items Constants.max_authorization_queue_items()

  # Validator Key Pairs Factory
  def validators_and_bandersnatch_keys(count \\ @validator_count) do
    {validators, key_pairs} =
      for _ <- 1..count do
        keypair = {_, b} = RingVrf.generate_secret_from_rand()
        {build(:validator, bandersnatch: b), keypair}
      end
      |> Enum.unzip()

    %{validators: validators, key_pairs: key_pairs}
  end

  def validators_and_ed25519_keys(count \\ @validator_count) do
    {validators, key_pairs} =
      for _ <- 1..count do
        {e, _} = keypair = :crypto.generate_key(:eddsa, :ed25519)

        {build(:validator, ed25519: e), keypair}
      end
      |> Enum.unzip()

    %{validators: validators, key_pairs: key_pairs}
  end

  # Seal Key Ticket Factory
  @spec single_seal_key_ticket_factory(list(), any(), integer()) :: System.State.SealKeyTicket.t()
  def single_seal_key_ticket_factory(key_pairs, entropy_pool, i) do
    {keypair, _} = Enum.at(key_pairs, rem(i, length(key_pairs)))

    attempt = Enum.random([0, 1])

    context = HeaderSeal.construct_seal_context(%{attempt: attempt}, entropy_pool)

    %SealKeyTicket{
      id: RingVrf.ietf_vrf_output(keypair, context),
      attempt: attempt
    }
  end

  def seal_key_ticket_factory(key_pairs, entropy_pool) do
    for i <- 0..(Constants.epoch_length() - 1),
        do: single_seal_key_ticket_factory(key_pairs, entropy_pool, i)
  end

  def genesis_state_factory do
    %{state: state} =
      build(:genesis_state_with_safrole)

    state
  end

  def genesis_state_with_safrole_factory(attrs) do
    validator_count = attrs[:validator_count] || @validator_count

    %{validators: validators, key_pairs: key_pairs} =
      validators_and_bandersnatch_keys(validator_count)

    public_keys = for {_, p} <- key_pairs, do: p
    RingVrf.init_ring_context(length(validators))

    entropy_pool = build(:entropy_pool)
    tickets = seal_key_ticket_factory(key_pairs, entropy_pool)

    safrole_state = %System.State.Safrole{
      pending: validators,
      epoch_root: RingVrf.create_commitment(public_keys),
      slot_sealers: tickets,
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
      specification: build(:availability_specification, work_package_hash: Hash.random()),
      refinement_context: build(:refinement_context),
      core_index: 1,
      authorizer_hash: Hash.two(),
      output: <<3>>,
      segment_root_lookup: %{},
      digests: build_list(2, :work_digest)
    }
  end

  def availability_specification_factory do
    %Block.Extrinsic.AvailabilitySpecification{
      work_package_hash: sequence(:work_package_hash, fn n -> <<n::256>> end),
      length: 2,
      erasure_root: Hash.three(),
      exports_root: Hash.four(),
      segment_count: 2
    }
  end

  def refinement_context_factory do
    %RefinementContext{
      anchor: Hash.one(),
      state_root: Hash.two(),
      beefy_root: Hash.three(),
      lookup_anchor: <<4::256>>,
      timeslot: 5
    }
  end

  def work_digest_factory do
    %WorkDigest{
      service: 0,
      code_hash: Hash.one(),
      payload_hash: Hash.two(),
      gas_ratio: 3,
      result: {:ok, <<4>>},
      imports: 5,
      exports: 6,
      extrinsic_count: 7,
      extrinsic_size: 8,
      gas_used: 9
    }
  end

  def work_item_factory do
    %Block.Extrinsic.WorkItem{
      service: 1,
      code_hash: Hash.one(),
      payload: <<2>>,
      refine_gas_limit: 3,
      import_segments: [{<<4::256>>, 5}],
      extrinsic: [{<<6::256>>, 7}],
      export_count: 8
    }
  end

  def work_package_factory do
    %Block.Extrinsic.WorkPackage{
      authorization_token: <<1>>,
      service: 2,
      authorization_code_hash: <<3::256>>,
      parameterization_blob: <<4>>,
      context: %RefinementContext{},
      work_items: [build(:work_item)]
    }
  end

  def work_package_and_its_extrinsic_factory do
    extrinsics = [<<1, 2, 3>>, <<4, 5, 6, 7>>]

    work_items =
      for wi <- build_list(2, :work_item) do
        put_in(wi.extrinsic, for(e <- extrinsics, do: {Hash.default(e), byte_size(e)}))
      end

    work_package = build(:work_package, work_items: work_items)

    {work_package, extrinsics ++ extrinsics}
  end

  # Validator Factories

  def validator_factory do
    %System.State.Validator{
      bandersnatch: Hash.random(),
      ed25519: Hash.random(),
      bls: :crypto.strong_rand_bytes(144),
      metadata: :crypto.strong_rand_bytes(128)
    }
  end

  # Ticket Factories
  def single_seal_key_ticket_factory do
    %System.State.SealKeyTicket{
      id: Hash.one(),
      attempt: 0
    }
  end

  def seal_key_ticket_factory do
    %System.State.SealKeyTicket{
      id: Hash.random(),
      attempt: sequence(:attempt, fn n -> rem(n, 2) end)
    }
  end

  # Safrole Factoriy
  def safrole_factory do
    %System.State.Safrole{
      pending: build_list(@validator_count, :validator),
      # Placeholder for epoch root
      epoch_root: :crypto.strong_rand_bytes(144),
      slot_sealers: build_list(Constants.epoch_length(), :seal_key_ticket),
      ticket_accumulator: build_list(Constants.epoch_length(), :seal_key_ticket)
    }
  end

  # Authorizer Factories
  def authorizer_queue_factory do
    for _ <- 1..@cores do
      for _ <- 1..@max_authorize_queue_items do
        unique_hash_factory()
      end
    end
  end

  def authorizer_pool_factory do
    for _ <- 1..@cores do
      for _ <- 1..@max_authorizers_per_core do
        unique_hash_factory()
      end
    end
  end

  def unique_hash_factory do
    Hash.random()
  end

  # Service Factories

  def services_factory do
    # Create a map with a single ServiceAccount
    %{1 => build(:service_account)}
  end

  def service_account_factory do
    storage_value = <<0xDEADBEEF::32>>
    preimage_value = <<0xBEEFCAFE::32>>
    hash = Hash.default(preimage_value)

    %System.State.ServiceAccount{
      storage: %{Hash.default(storage_value) => storage_value},
      preimage_storage_p: %{hash => preimage_value},
      preimage_storage_l: %{{hash, 4} => [1, 2, 3]},
      code_hash: Hash.default(storage_value),
      balance: 1000,
      gas_limit_g: 5000,
      gas_limit_m: 10_000
    }
  end

  # Entropy Pool Factory

  def entropy_pool_factory do
    %System.State.EntropyPool{
      n0: Hash.random(),
      n1: unique_hash_factory(),
      n2: unique_hash_factory(),
      n3: unique_hash_factory()
    }
  end

  def fixed_entropy_pool_factory do
    %System.State.EntropyPool{n0: Hash.one(), n1: Hash.two(), n2: Hash.three(), n3: Hash.four()}
  end

  # Core Reports Factory
  def core_report_factory do
    %System.State.CoreReport{
      work_report: build(:work_report),
      timeslot: sequence(:core_report_timeslot, & &1)
    }
  end

  def privileged_services_factory do
    %System.State.PrivilegedServices{
      privileged_services_service: 1,
      authorizer_queue_service: 2,
      next_validators_service: 3,
      services_gas: %{1 => 1000, 2 => 2000, 3 => 3000}
    }
  end

  def verdict_factory do
    %Block.Extrinsic.Disputes.Verdict{
      epoch_index: Time.epoch_index(build(:header).timeslot),
      work_report_hash: Hash.random(),
      judgements: build_list(1, :judgement)
    }
  end

  def judgement_factory(attrs) do
    work_report_hash = attrs[:work_report_hash] || Hash.random()
    {_, priv} = attrs[:key_pair] || :crypto.generate_key(:eddsa, :ed25519)

    vote = Map.get(attrs, :vote, true)

    signature =
      if vote do
        Util.Crypto.sign(SigningContexts.jam_valid() <> work_report_hash, priv)
      else
        Util.Crypto.sign(SigningContexts.jam_invalid() <> work_report_hash, priv)
      end

    %Block.Extrinsic.Disputes.Judgement{
      validator_index: attrs[:validator_index] || 0,
      vote: vote,
      signature: signature
    }
  end

  def culprit_factory(attrs) do
    work_report_hash = attrs[:work_report_hash] || Hash.random()
    {pub, priv} = attrs[:key_pair] || :crypto.generate_key(:eddsa, :ed25519)

    %Block.Extrinsic.Disputes.Culprit{
      work_report_hash: work_report_hash,
      key: pub,
      signature: Util.Crypto.sign(SigningContexts.jam_guarantee() <> work_report_hash, priv)
    }
  end

  def fault_factory(attrs) do
    work_report_hash = attrs[:work_report_hash] || Hash.random()
    {pub, priv} = attrs[:key_pair] || :crypto.generate_key(:eddsa, :ed25519)
    vote = Map.get(attrs, :vote, true)

    signature_base =
      if vote do
        SigningContexts.jam_valid()
      else
        SigningContexts.jam_invalid()
      end

    %Block.Extrinsic.Disputes.Fault{
      work_report_hash: work_report_hash,
      vote: vote,
      key: pub,
      signature: Util.Crypto.sign(signature_base <> work_report_hash, priv)
    }
  end

  # Judgements Factory
  def judgements_factory do
    %System.State.Judgements{
      good: MapSet.new([Hash.random()]),
      bad: MapSet.new([Hash.random()]),
      wonky: MapSet.new([Hash.random()]),
      offenders: MapSet.new([Hash.random()])
    }
  end

  # Validator Statistics Factory
  def validator_statistics_factory(attrs) do
    count = attrs[:count] || @validator_count

    %System.State.ValidatorStatistics{
      current_epoch_statistics: build_list(count, :statistics),
      previous_epoch_statistics: build_list(count, :statistics),
      core_statistics: attrs[:core_statistics] || build_list(@cores, :core_statistics),
      service_statistics:
        attrs[:service_statistics] ||
          %{
            1 => build(:service_statistics),
            2 => build(:service_statistics)
          }
    }
  end

  def service_statistics_factory do
    %System.State.ServiceStatistic{
      preimage: {10, 1000},
      refine: {10_000, 500_000},
      imports: 1_000_000,
      exports: 10_000_000,
      extrinsic_count: 100_000_000,
      extrinsic_size: 1,
      accumulation: {9, 1},
      transfers: {1000, 100_000}
    }
  end

  def core_statistics_factory do
    %System.State.CoreStatistic{
      da_load: 1,
      popularity: 10,
      imports: 100,
      exports: 1_000,
      extrinsic_size: 10_000,
      extrinsic_count: 100_000,
      bundle_size: 1_000_000,
      gas_used: 1_000_000_000
    }
  end

  def statistics_factory do
    %System.State.ValidatorStatistic{
      availability_assurances: 6,
      blocks_produced: 100,
      da_load: 1000,
      preimages_introduced: 100_000,
      reports_guaranteed: 1_000_000,
      tickets_introduced: 1000
    }
  end

  def block_factory do
    %Block{
      extrinsic: build(:extrinsic),
      header: build(:header)
    }
  end

  def decodable_block_factory(attrs) do
    extrinsic = build(:extrinsic, tickets: [build(:ticket_proof)], disputes: build(:disputes))
    parent_hash = Map.get(attrs, :parent_hash, Hash.random())

    header =
      build(:decodable_header,
        extrinsic_hash: Hash.default(Encodable.encode(extrinsic)),
        parent_hash: parent_hash
      )

    build(
      :block,
      merge_attributes(Map.delete(attrs, :parent_hash), %{header: header, extrinsic: extrinsic})
    )
  end

  def safrole_block_factory(attrs) do
    state = attrs[:state]
    timeslot = attrs[:timeslot] || 1

    block_author_key_index =
      attrs[:block_author_key_index] || rem(timeslot, length(state.curr_validators))

    block_author_key_pair = Enum.at(attrs[:key_pairs], block_author_key_index)

    # Build and seal the header dynamically with the correct timeslot
    header =
      System.HeaderSeal.seal_header(
        build(:header, timeslot: timeslot, block_author_key_index: block_author_key_index),
        state.safrole.slot_sealers,
        state.entropy_pool,
        block_author_key_pair
      )

    %Block{
      extrinsic: attrs[:extrinsic] || build(:extrinsic),
      header: header
    }
  end

  def disputes_factory do
    %Disputes{
      verdicts: build_list(2, :verdict),
      culprits: build_list(2, :culprit),
      faults: build_list(2, :fault)
    }
  end

  def extrinsic_factory do
    %Extrinsic{
      tickets: [%TicketProof{}],
      disputes: %Disputes{},
      preimages: build_list(2, :preimage),
      assurances: [],
      guarantees:
        for(i <- 1..3, do: build(:guarantee, work_report: build(:work_report, core_index: i)))
    }
  end

  def header_factory do
    %Header{
      timeslot: 5,
      parent_hash: Hash.random(),
      prior_state_root: Hash.random(),
      # Ho
      offenders_marker: [Hash.random()],
      # Hi
      block_author_key_index: 0
    }
  end

  def decodable_header_factory(attrs) do
    build(
      :header,
      Map.merge(attrs, %{
        prior_state_root: Hash.random(),
        epoch_mark:
          {Hash.random(), Hash.random(),
           for(_ <- 1..Constants.validator_count(), do: {Hash.random(), Hash.random()})},
        vrf_signature: Hash.random(96),
        block_seal: Hash.random(96)
      })
    )
  end

  def guarantee_factory do
    %Guarantee{
      work_report: build(:work_report),
      timeslot: 5,
      credentials: credentials_list()
    }
  end

  def recent_history_factory do
    alias System.State.RecentHistory

    %RecentHistory{
      blocks: build_list(2, :recent_block)
    }
  end

  def recent_block_factory do
    %RecentBlock{
      header_hash: Hash.random(),
      state_root: Hash.random(),
      accumulated_result_mmr: [Hash.random(), nil, nil],
      work_report_hashes: %{Hash.random() => Hash.random()}
    }
  end

  defp credentials_list do
    for(i <- 1..Enum.random(2..3), do: {i, Crypto.random_sign()})
    |> Enum.sort_by(&elem(&1, 0))
  end

  def preimage_factory do
    id = sequence(:preimage, & &1)
    %Preimage{service: id, blob: <<1, 2, 3, 4, id>>}
  end

  def assurance_factory do
    hash = String.duplicate("a", @hash_size)
    bitfield = String.duplicate("x", Sizes.bitfield())
    signature = String.duplicate("y", @signature_size)

    %Assurance{
      hash: hash,
      bitfield: bitfield,
      validator_index: 1,
      signature: signature
    }
  end

  def ticket_proof_factory do
    %TicketProof{
      attempt: 1,
      signature: Hash.random(@bandersnatch_proof_size)
    }
  end

  def ready_to_accumulate_factory(_attrs) do
    for(_ <- 1..Constants.epoch_length(), do: build_list(1, :ready))
  end

  def ready_factory do
    %System.State.Ready{
      work_report: build(:work_report),
      dependencies: MapSet.new([Hash.random(), Hash.random()])
    }
  end

  def accumulation_history_factory(_attrs) do
    for(_ <- 1..Constants.epoch_length(), do: MapSet.new([Hash.random()]))
  end

  def shuffle_hash_factory do
    Hash.default(<<"This generates the shuffle hash for testing">>)
  end
end
