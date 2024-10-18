defmodule Block.Extrinsic.GuaranteeTest do
  use ExUnit.Case
  import Jamixir.Factory

  alias System.State.ServiceAccount
  alias System.State.RecentHistory
  alias System.State.RecentHistory.RecentBlock
  alias Block.Extrinsic.{Guarantee, Guarantor}
  alias System.State
  alias Util.{Crypto, Hash}

  defmodule GuaranteeConstantsMock do
    def validator_count, do: 6
    def core_count, do: 2
    def rotation_period, do: 10
    def gas_accumulation, do: 1000
  end

  describe "validate/1" do
    setup do
      refinement_context =
        build(:refinement_context,
          anchor: <<99>>,
          state_root_: <<77>>,
          beefy_root_: Hash.keccak_256(Codec.Encoder.encode_mmr([<<1>>, <<2>>]))
        )

      g1 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 1, refinement_context: refinement_context),
          timeslot: 100,
          credentials: [{1, <<3::512>>}, {2, <<4::512>>}]
        )

      g2 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 2, refinement_context: refinement_context),
          timeslot: 100,
          credentials: [{1, <<1::512>>}, {2, <<2::512>>}]
        )

      state = %State{
        services: %{0 => %ServiceAccount{code_hash: Hash.one()}},
        recent_history: %RecentHistory{
          blocks: [
            %RecentBlock{
              header_hash: refinement_context.anchor,
              state_root: refinement_context.state_root_,
              accumulated_result_mmr: [<<1>>, <<2>>]
            }
          ]
        }
      }

      {:ok, g1: g1, g2: g2, state: state, refinement_context: refinement_context}
    end

    test "returns :ok for valid guarantees", %{state: state, g1: g1, g2: g2} do
      assert Guarantee.validate([g1, g2], state, 1) == :ok
    end

    test "returns error when work report size is invalid", %{state: state, g1: g1} do
      invalid_g1 =
        update_in(g1.work_report.output, fn _ ->
          String.duplicate("a", Constants.max_work_report_size() + 1)
        end)

      assert Guarantee.validate([invalid_g1], state, 1) ==
               {:error, "Invalid work report size"}
    end

    test "returns error for guarantees not ordered by core_index", %{state: state, g1: g1, g2: g2} do
      assert Guarantee.validate([g2, g1], state, 1) == {:error, :not_in_order}
    end

    test "returns error for duplicate core_index in guarantees", %{state: state, g1: g1} do
      assert Guarantee.validate([g1, g1], state, 1) == {:error, :duplicates}
    end

    test "returns error for invalid credential length", %{g1: g1, state: state} do
      invalid_g1 = put_in(g1.credentials, [{1, <<1::512>>}])

      assert Guarantee.validate([invalid_g1], state, 1) ==
               {:error, "Invalid credentials in guarantees"}
    end

    test "returns error for credentials not ordered by validator_index", %{g1: g1, state: state} do
      invalid_g1 = put_in(g1.credentials, [{2, <<1::512>>}, {1, <<2::512>>}])

      assert Guarantee.validate([invalid_g1], state, 1) ==
               {:error, "Invalid credentials in guarantees"}
    end

    test "returns error for duplicate validator_index in credentials", %{g1: g1, state: state} do
      invalid_g1 = put_in(g1.credentials, [{1, <<1::512>>}, {1, <<2::512>>}])

      assert Guarantee.validate([invalid_g1], state, 1) ==
               {:error, "Invalid credentials in guarantees"}
    end

    test "handles empty list of guarantees", context do
      assert Guarantee.validate([], context.state, 1) == :ok
    end

    test "validates a single guarantee correctly", context do
      assert Guarantee.validate([context.g1], context.state, 1) == :ok
    end

    test "passes when gas accumulation is within limits", %{state: state, g1: g1, g2: g2} do
      wr1 = build(:work_result, service: 1, gas_ratio: 400)
      wr2 = build(:work_result, service: 2, gas_ratio: 300)

      guarantees = [
        put_in(g1.work_report.results, [wr1]),
        put_in(g2.work_report.results, [wr2])
      ]

      s =
        put_in(state.services, %{
          1 => %ServiceAccount{gas_limit_g: 300, code_hash: Hash.one()},
          2 => %ServiceAccount{gas_limit_g: 200, code_hash: Hash.one()}
        })

      assert Guarantee.validate(guarantees, s, 1) == :ok
    end

    test "fails when a work result references a non-existent service",
         %{state: state, g1: g1, g2: g2} do
      wr1 = build(:work_result, service: 1, gas_ratio: 400)
      # Non-existent service
      wr2 = build(:work_result, service: 3, gas_ratio: 300)

      guarantees = [
        put_in(g1.work_report.results, [wr1]),
        put_in(g2.work_report.results, [wr2])
      ]

      s =
        put_in(state.services, %{
          1 => %ServiceAccount{gas_limit_g: 300, code_hash: Hash.one()},
          2 => %ServiceAccount{gas_limit_g: 200, code_hash: Hash.one()}
        })

      assert Guarantee.validate(guarantees, s, 1) == {:error, :non_existent_service}
    end

    test "fails when total gas exceeds Constants.gas_accumulation()",
         %{state: state, g1: g1, g2: g2} do
      wr1 = build(:work_result, service: 1, gas_ratio: 999)
      wr2 = build(:work_result, service: 2, gas_ratio: 600)
      wr3 = build(:work_result, service: 1, gas_ratio: 401)

      guarantees = [
        put_in(g1.work_report.results, [wr1]),
        put_in(g2.work_report.results, [wr2, wr3])
      ]

      s =
        put_in(state.services, %{
          1 => %ServiceAccount{gas_limit_g: 300, code_hash: Hash.one()},
          2 => %ServiceAccount{gas_limit_g: 200, code_hash: Hash.one()}
        })

      assert Guarantee.validate(guarantees, s, 1) == {:error, :invalid_gas_accumulation}
    end

    test "fails when gas_ratio is less than service's gas_limit_g",
         %{state: state, g1: g1, g2: g2} do
      wr1 = build(:work_result, service: 1, gas_ratio: 299)
      wr2 = build(:work_result, service: 2, gas_ratio: 300)

      guarantees = [
        put_in(g1.work_report.results, [wr1]),
        put_in(g2.work_report.results, [wr2])
      ]

      s =
        put_in(state.services, %{
          1 => %ServiceAccount{gas_limit_g: 300, code_hash: Hash.one()},
          2 => %ServiceAccount{gas_limit_g: 200, code_hash: Hash.one()}
        })

      assert Guarantee.validate(guarantees, s, 1) ==
               {:error, :insufficient_gas_ratio}
    end

    test "error when service code_hash mismatch", %{state: state, g1: g1, g2: g2} do
      s = put_in(state.services[0].code_hash, Hash.two())
      assert Guarantee.validate([g1, g2], s, 1) == {:error, :invalid_work_result_core_index}
    end

    test "returns error when duplicated work package hash", %{g1: g1, g2: g2, state: state} do
      updated_g2 =
        put_in(
          g2.work_report.specification.work_package_hash,
          g1.work_report.specification.work_package_hash
        )

      assert Guarantee.validate([g1, updated_g2], state, 1) == {:error, :duplicated_wp_hash}
    end

    test "returns error when refinement context timeslot is too old", %{g1: g1, state: state} do
      current_timeslot = 1000
      old_timeslot = current_timeslot - Constants.max_age_lookup_anchor() - 1
      invalid_g = put_in(g1.work_report.refinement_context.timeslot, old_timeslot)

      assert Guarantee.validate([invalid_g], state, current_timeslot) ==
               {:error, :refine_context_timeslot}
    end

    test "error when recent history does not have header_hash", %{g1: g1, state: state} do
      valid_rh = state.recent_history
      valid_rb = Enum.at(valid_rh.blocks, 0)
      invalid_rb = %RecentBlock{valid_rb | header_hash: nil}
      s = put_in(state.recent_history, %RecentHistory{valid_rh | blocks: [invalid_rb]})

      assert Guarantee.validate([g1], s, 1) == {:error, :invalid_anchor_block}
    end

    test "error when recent history does not have state_root", %{g1: g1, state: state} do
      invalid_rb = put_in(Enum.at(state.recent_history.blocks, 0).state_root, nil)
      invalid_state = put_in(state.recent_history.blocks, [invalid_rb])

      assert Guarantee.validate([g1], invalid_state, 1) == {:error, :invalid_anchor_block}
    end

    test "error when recent history does not have accumulated_result_mmr", %{g1: g1, state: state} do
      invalid_rb = put_in(Enum.at(state.recent_history.blocks, 0).accumulated_result_mmr, [])
      invalid_state = put_in(state.recent_history.blocks, [invalid_rb])

      assert Guarantee.validate([g1], invalid_state, 1) == {:error, :invalid_anchor_block}
    end

    test "returns error when work package is in recent history", %{g1: g1, state: state} do
      wp_hash = g1.work_report.specification.work_package_hash
      # Add the new work package hash to the recent history
      recent_blocks = [%{hd(state.recent_history.blocks) | work_report_hashes: [wp_hash]}]
      new_state = %{state | recent_history: %RecentHistory{blocks: recent_blocks}}

      assert Guarantee.validate([g1], new_state, 1) == {:error, :work_package_in_recent_history}
    end

    test "validates prerequisite", %{g1: g1, g2: g2, state: state} do
      # (wx)p ≠ ∅
      updated_g1 = put_in(g1.work_report.refinement_context.prerequisite, "hash")
      assert Guarantee.validate([updated_g1, g2], state, 1) == {:error, :invalid_prerequisite}

      # (wx)p ∈ p
      valid_g1 = put_in(g1.work_report.specification.work_package_hash, "hash")
      assert Guarantee.validate([valid_g1, g2], state, 1) == :ok

      # (wx)p ∈ bp, b ∈ β
      valid_rb = put_in(Enum.at(state.recent_history.blocks, 0).work_report_hashes, ["hash"])
      valid_state = put_in(state.recent_history.blocks, [valid_rb])
      assert Guarantee.validate([updated_g1, g2], valid_state, 1) == :ok
    end
  end

  describe "reporters_set/6" do
    setup do
      Application.put_env(:jamixir, Constants, GuaranteeConstantsMock)

      on_exit(fn ->
        Application.delete_env(:jamixir, Constants)
      end)

      entropy_pool = build(:entropy_pool)

      %{validators: curr_validators, key_pairs: curr_key_pairs} =
        validators_and_ed25519_keys(6)

      %{validators: prev_validators, key_pairs: prev_key_pairs} =
        validators_and_ed25519_keys(6)

      offenders = MapSet.new()
      timeslot = 15

      curr_guarantor =
        Guarantor.guarantors(
          entropy_pool.n2,
          timeslot,
          curr_validators,
          offenders
        )

      prev_guarantor =
        Guarantor.prev_guarantors(
          entropy_pool.n2,
          entropy_pool.n3,
          timeslot,
          curr_validators,
          prev_validators,
          offenders
        )

      %{
        entropy_pool: entropy_pool,
        curr_validators: curr_validators,
        prev_validators: prev_validators,
        curr_key_pairs: curr_key_pairs,
        prev_key_pairs: prev_key_pairs,
        offenders: offenders,
        timeslot: timeslot,
        curr_guarantor: curr_guarantor,
        prev_guarantor: prev_guarantor
      }
    end

    test "returns correct set of reporters for valid guarantees", context do
      guarantees = create_valid_guarantees(context)

      {:ok, reporters} =
        Guarantee.reporters_set(
          guarantees,
          context.entropy_pool,
          context.timeslot,
          context.curr_validators,
          context.prev_validators,
          context.offenders
        )

      assert is_map(reporters)
      # All validators should be reporters
      assert MapSet.size(reporters) == 6
    end

    test "uses previous guarantor when timeslot is in previous rotation period", context do
      prev_timeslot = context.timeslot - GuaranteeConstantsMock.rotation_period()

      guarantees =
        create_valid_guarantees(%{
          context
          | timeslot: prev_timeslot,
            curr_guarantor: context.prev_guarantor
        })

      {:ok, reporters} =
        Guarantee.reporters_set(
          guarantees,
          context.entropy_pool,
          context.timeslot,
          context.curr_validators,
          context.prev_validators,
          context.offenders
        )

      assert MapSet.size(reporters) == 6
    end

    test "returns error for invalid signature", context do
      [valid_guarantee | _] = create_valid_guarantees(context)
      invalid_guarantee = %{valid_guarantee | credentials: [{0, <<1::512>>}, {1, <<2::512>>}]}

      result =
        Guarantee.reporters_set(
          [invalid_guarantee],
          context.entropy_pool,
          context.timeslot,
          context.curr_validators,
          context.prev_validators,
          context.offenders
        )

      assert result == {:error, "Invalid signature in guarantee"}
    end

    test "returns error when guarantee timeslot is greater than current timeslot", context do
      [valid_guarantee | _] = create_valid_guarantees(context)
      invalid_guarantee = %{valid_guarantee | timeslot: context.timeslot + 1}

      result =
        Guarantee.reporters_set(
          [invalid_guarantee],
          context.entropy_pool,
          context.timeslot,
          context.curr_validators,
          context.prev_validators,
          context.offenders
        )

      assert result == {:error, "Invalid timeslot in guarantee"}
    end

    test "returns error when guarantee timeslot is too old", context do
      old_timeslot = context.timeslot - GuaranteeConstantsMock.rotation_period() * 2
      guarantees = create_valid_guarantees(%{context | timeslot: old_timeslot})

      result =
        Guarantee.reporters_set(
          guarantees,
          context.entropy_pool,
          context.timeslot,
          context.curr_validators,
          context.prev_validators,
          context.offenders
        )

      assert result == {:error, "Invalid core_index in guarantee"}
    end
  end

  # Formula (143) v0.4.1
  describe "validate_availability/4" do
    setup do
      guarantees = [
        build(:guarantee, work_report: build(:work_report, core_index: 0, authorizer_hash: <<1>>)),
        build(:guarantee, work_report: build(:work_report, core_index: 1, authorizer_hash: <<2>>))
      ]

      {:ok, guarantees: guarantees}
    end

    test "returns :missing_authorizer when authorizer is not in the pool", %{
      guarantees: guarantees
    } do
      core_reports = [nil, nil]
      authorizer_pool = [MapSet.new([<<3>>]), MapSet.new([<<2>>])]

      result =
        Guarantee.validate_availability(guarantees, core_reports, 100, authorizer_pool)

      assert result == {:error, :missing_authorizer}
    end

    test "returns :pending_work when there's pending work", %{guarantees: guarantees} do
      core_reports = [%{timeslot: 94}, %{timeslot: 80}]
      authorizer_pool = [MapSet.new([<<1>>]), MapSet.new([<<2>>])]

      result =
        Guarantee.validate_availability(guarantees, core_reports, 100, authorizer_pool)

      assert result == {:error, :pending_work}
    end

    test "returns :ok when all conditions are met", %{guarantees: guarantees} do
      core_reports = [%{timeslot: 95}, %{timeslot: 105}]
      authorizer_pool = [MapSet.new([<<1>>]), MapSet.new([<<2>>])]

      result =
        Guarantee.validate_availability(guarantees, core_reports, 100, authorizer_pool)

      assert result == :ok
    end
  end

  defp create_valid_guarantees(context) do
    Enum.map(0..1, fn core_index ->
      work_report = build(:work_report, core_index: core_index)
      create_valid_guarantee(work_report, context)
    end)
  end

  defp create_valid_guarantee(work_report, context) do
    guarantor = context.curr_guarantor
    payload = SigningContexts.jam_guarantee() <> Hash.default(Codec.Encoder.encode(work_report))

    assigned_validators =
      Enum.with_index(guarantor.validators)
      |> Enum.filter(fn {_, index} ->
        Enum.at(guarantor.assigned_cores, index) == work_report.core_index
      end)
      |> Enum.map(fn {validator, _} -> validator end)

    credentials =
      Enum.map(assigned_validators, fn validator ->
        index = Enum.find_index(context.curr_validators, &(&1.ed25519 == validator.ed25519))
        {_, priv} = Enum.at(context.curr_key_pairs, index)

        signature = Crypto.sign(payload, priv)

        {index, signature}
      end)

    build(:guarantee,
      work_report: work_report,
      timeslot: context.timeslot,
      credentials: credentials
    )
  end

  describe "encode / decode" do
    test "encode/decode" do
      guarantee = build(:guarantee)
      encoded = Encodable.encode(guarantee)
      {decoded, _} = Guarantee.decode(encoded)
      assert guarantee == decoded
    end
  end
end
