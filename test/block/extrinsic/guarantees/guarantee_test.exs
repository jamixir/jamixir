defmodule Block.Extrinsic.GuaranteeTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.{Guarantee, Guarantor}
  alias System.State
  alias System.State.{CoreReport, Ready, RecentHistory, RecentHistory.RecentBlock, ServiceAccount}
  alias Util.{Crypto, Hash}
  import TestHelper

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
          work_report:
            build(:work_report,
              core_index: 1,
              refinement_context: refinement_context,
              segment_root_lookup: %{}
            ),
          timeslot: 6,
          credentials: [{1, <<3::512>>}, {2, <<4::512>>}]
        )

      g2 =
        build(:guarantee,
          work_report:
            build(:work_report,
              core_index: 2,
              refinement_context: refinement_context,
              segment_root_lookup: %{}
            ),
          timeslot: 6,
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

      invalid_g1 = put_in(invalid_g1.work_report.segment_root_lookup, %{})

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
      wr1 = build(:work_result, service: 1, gas_ratio: 99_900)
      wr2 = build(:work_result, service: 2, gas_ratio: 60_000)
      wr3 = build(:work_result, service: 1, gas_ratio: 40_100)

      guarantees = [
        put_in(g1.work_report.results, [wr1]),
        put_in(g2.work_report.results, [wr2, wr3])
      ]

      s =
        put_in(state.services, %{
          1 => %ServiceAccount{gas_limit_g: 30_000, code_hash: Hash.one()},
          2 => %ServiceAccount{gas_limit_g: 20_000, code_hash: Hash.one()}
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

    test "returns error when work package exists in recent history", %{state: state, g1: g1} do
      # Add the work package hash to recent history
      wp_hash = g1.work_report.specification.work_package_hash
      block = %{hd(state.recent_history.blocks) | work_report_hashes: %{wp_hash => "hash"}}
      s = put_in(state.recent_history.blocks, [block])

      assert Guarantee.validate([g1], s, 1) == {:error, :work_package_already_exists}
    end

    test "returns error when work package exists in accumulation history", %{state: state, g1: g1} do
      # Add the work package hash to accumulation history
      wp_hash = g1.work_report.specification.work_package_hash
      s = put_in(state.accumulation_history, [MapSet.new([wp_hash])])

      assert Guarantee.validate([g1], s, 1) == {:error, :work_package_already_exists}
    end

    test "returns error when segment root lookup value mismatches", %{state: state, g1: g1} do
      # Add a hash to recent history
      block = %{
        hd(state.recent_history.blocks)
        | work_report_hashes: %{"hash1" => "correct_export"}
      }

      s = put_in(state.recent_history.blocks, [block])
      invalid_g1 = put_in(g1.work_report.segment_root_lookup, %{"hash1" => "wrong_export"})

      assert Guarantee.validate([invalid_g1], s, 1) ==
               {:error, :invalid_segment_root_lookup}
    end
  end

  describe "reporters_set/6" do
    setup_constants do
      def gas_accumulation, do: 1000
    end

    setup do
      entropy_pool = build(:entropy_pool)

      %{validators: curr_validators, key_pairs: curr_key_pairs} =
        validators_and_ed25519_keys(Constants.validator_count())

      %{validators: prev_validators, key_pairs: prev_key_pairs} =
        validators_and_ed25519_keys(Constants.validator_count())

      offenders = MapSet.new()
      timeslot = 2

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
      prev_timeslot = context.timeslot - Constants.rotation_period()

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
      old_timeslot = context.timeslot - Constants.rotation_period() * 2
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
    for core_index <- 0..(Constants.core_count() - 1) do
      create_valid_guarantee(build(:work_report, core_index: core_index), context)
    end
  end

  defp create_valid_guarantee(work_report, context) do
    guarantor = context.curr_guarantor
    payload = SigningContexts.jam_guarantee() <> Hash.default(Codec.Encoder.encode(work_report))

    assigned_validators =
      for {validator, index} <- Enum.with_index(guarantor.validators),
          Enum.at(guarantor.assigned_cores, index) == work_report.core_index,
          do: validator

    credentials =
      for validator <- assigned_validators do
        index = Enum.find_index(context.curr_validators, &(&1.ed25519 == validator.ed25519))
        {_, priv} = Enum.at(context.curr_key_pairs, index)

        signature = Crypto.sign(payload, priv)

        {index, signature}
      end

    build(:guarantee,
      work_report: work_report,
      timeslot: context.timeslot,
      credentials: credentials
    )
  end

  describe "collect_prerequisites/1" do
    setup do
      base_struct = %{
        work_report: %WorkReport{
          refinement_context: %RefinementContext{
            prerequisite: MapSet.new([Hash.one()])
          }
        }
      }

      r2 =
        put_in(
          base_struct.work_report.refinement_context.prerequisite,
          MapSet.new([Hash.two()])
        )

      r_nil =
        put_in(
          base_struct.work_report.refinement_context.prerequisite,
          MapSet.new()
        )

      {:ok, r1: base_struct, r2: r2, r_nil: r_nil}
    end

    test "returns empty MapSet for empty list" do
      assert Guarantee.collect_prerequisites([]) == MapSet.new()
    end

    test "collects unique prerequisite hashes", %{r1: r1, r2: r2} do
      assert Guarantee.collect_prerequisites([r1, r2, r1]) ==
               MapSet.new([Hash.one(), Hash.two()])
    end

    test "handles nil items", %{r1: r1} do
      assert Guarantee.collect_prerequisites([nil, r1, nil]) ==
               MapSet.new([Hash.one()])
    end

    test "filters out nil prerequisites", %{r1: r1, r_nil: r_nil} do
      assert Guarantee.collect_prerequisites([r1, r_nil]) ==
               MapSet.new([Hash.one()])
    end

    test "combines multiple prerequisite hashes from different reports" do
      r1 = %{
        work_report: %WorkReport{
          refinement_context: %RefinementContext{
            prerequisite: MapSet.new([Hash.one(), Hash.two(), Hash.three()])
          }
        }
      }

      r2 = %{
        work_report: %WorkReport{
          refinement_context: %RefinementContext{
            prerequisite: MapSet.new([Hash.four(), Hash.five()])
          }
        }
      }

      assert Guarantee.collect_prerequisites([r1, r2]) ==
               MapSet.new([Hash.one(), Hash.two(), Hash.three(), Hash.four(), Hash.five()])
    end
  end

  describe "validate_new_work_packages/5" do
    setup do
      offending_work_report =
        put_in(
          build(:work_report),
          [Access.key(:refinement_context), Access.key(:prerequisite)],
          MapSet.new(["wrh"])
        )

      work_reports = [
        put_in(
          build(:work_report),
          [Access.key(:specification), Access.key(:work_package_hash)],
          "wrh"
        )
      ]

      recent_blocks = [
        %RecentBlock{
          header_hash: "hash1",
          state_root: "root1",
          accumulated_result_mmr: ["mmr1"],
          work_report_hashes: %{}
        }
      ]

      {:ok,
       work_reports: work_reports,
       recent_blocks: recent_blocks,
       accumulation_history: [],
       ready_to_accumulate: [[]],
       core_reports: [],
       offending_work_report: offending_work_report}
    end

    test "rejects when hash exists in recent history", context do
      blocks = [%{hd(context.recent_blocks) | work_report_hashes: %{"wrh" => "export1"}}]

      assert Guarantee.validate_new_work_packages(
               context.work_reports,
               %RecentHistory{blocks: blocks},
               context.accumulation_history,
               context.ready_to_accumulate,
               context.core_reports
             ) == {:error, :work_package_already_exists}
    end

    test "rejects when hash exists in accumulation history", context do
      accumulation_history = [MapSet.new(["wrh"])]

      assert Guarantee.validate_new_work_packages(
               context.work_reports,
               %RecentHistory{blocks: context.recent_blocks},
               accumulation_history,
               context.ready_to_accumulate,
               context.core_reports
             ) == {:error, :work_package_already_exists}
    end

    test "rejects when hash exists in ready to accumulate", context do
      ready = [
        %Ready{work_report: context.offending_work_report}
      ]

      assert Guarantee.validate_new_work_packages(
               context.work_reports,
               %RecentHistory{blocks: context.recent_blocks},
               context.accumulation_history,
               ready,
               context.core_reports
             ) == {:error, :work_package_already_exists}
    end

    test "rejects when hash exists in core reports", context do
      core_reports = [%CoreReport{work_report: context.offending_work_report}]

      assert Guarantee.validate_new_work_packages(
               context.work_reports,
               %RecentHistory{blocks: context.recent_blocks},
               context.accumulation_history,
               context.ready_to_accumulate,
               core_reports
             ) == {:error, :work_package_already_exists}
    end

    test "accepts when hashes are disjoint from all sources", context do
      assert Guarantee.validate_new_work_packages(
               context.work_reports,
               %RecentHistory{blocks: context.recent_blocks},
               context.accumulation_history,
               context.ready_to_accumulate,
               context.core_reports
             ) == :ok
    end
  end

  describe "encode / decode" do
    test "encode/decode" do
      guarantee = build(:guarantee)
      encoded = Encodable.encode(guarantee)
      {decoded, _} = Guarantee.decode(encoded)
      assert guarantee == decoded
    end
  end

  describe "validate_prerequisites/2" do
    setup do
      work_report =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new(["prereq_hash"])},
          segment_root_lookup: %{"segment_hash1" => "value1", "segment_hash2" => "value2"}
        )

      recent_blocks = [
        %RecentBlock{work_report_hashes: %{"some_hash" => "value", "segment_hash1" => "value1"}}
      ]

      {:ok, work_report: work_report, recent_blocks: recent_blocks}
    end

    test "fails when prerequisite hash is missing", %{
      work_report: work_report,
      recent_blocks: recent_blocks
    } do
      assert {:error, :missing_prerequisite_work_packages} ==
               Guarantee.validate_prerequisites([work_report], %RecentHistory{
                 blocks: recent_blocks
               })
    end

    test "fails when segment root lookup hash is missing", %{
      work_report: work_report,
      recent_blocks: recent_blocks
    } do
      blocks = [
        %{
          hd(recent_blocks)
          | work_report_hashes: %{"prereq_hash" => "value", "segment_hash1" => "value1"}
        }
      ]

      assert {:error, :missing_prerequisite_work_packages} ==
               Guarantee.validate_prerequisites([work_report], %RecentHistory{blocks: blocks})
    end

    test "succeeds when all required hashes are present", %{
      work_report: work_report,
      recent_blocks: recent_blocks
    } do
      blocks = [
        %{
          hd(recent_blocks)
          | work_report_hashes: %{
              "prereq_hash" => "value",
              "segment_hash1" => "value1",
              "segment_hash2" => "value2"
            }
        }
      ]

      assert :ok ==
               Guarantee.validate_prerequisites([work_report], %RecentHistory{blocks: blocks})
    end

    test "succeeds when prerequisite points to any work package in extrinsic", %{
      recent_blocks: recent_blocks
    } do
      dependent_report =
        build(:work_report,
          refinement_context: %{prerequisite: MapSet.new(["other_hash"])},
          segment_root_lookup: %{}
        )

      other_report =
        build(:work_report,
          specification: %{work_package_hash: "other_hash"},
          segment_root_lookup: %{}
        )

      blocks = [%{hd(recent_blocks) | work_report_hashes: %{}}]

      assert :ok ==
               Guarantee.validate_prerequisites([dependent_report, other_report], %RecentHistory{
                 blocks: blocks
               })
    end
  end

  describe "validate_segment_root_lookups/2" do
    setup do
      work_report1 =
        build(:work_report,
          specification: %{work_package_hash: "hash1", exports_root: "export1"},
          segment_root_lookup: %{"hash1" => "export1", "hash2" => "export2"}
        )

      recent_blocks = [
        %RecentBlock{work_report_hashes: %{"hash2" => "export2", "hash3" => "export3"}}
      ]

      {:ok, work_report1: work_report1, recent_blocks: recent_blocks}
    end

    test "fails when segment_root_lookup has key not in combined map", %{
      work_report1: work_report1,
      recent_blocks: recent_blocks
    } do
      invalid_report = put_in(work_report1.segment_root_lookup, %{"missing_hash" => "export1"})

      assert {:error, :invalid_segment_root_lookup} ==
               Guarantee.validate_segment_root_lookups([invalid_report], %RecentHistory{
                 blocks: recent_blocks
               })
    end

    test "fails when value mismatches for existing key", %{
      work_report1: work_report1,
      recent_blocks: recent_blocks
    } do
      invalid_report = put_in(work_report1.segment_root_lookup, %{"hash2" => "wrong_export"})

      assert {:error, :invalid_segment_root_lookup} ==
               Guarantee.validate_segment_root_lookups([invalid_report], %RecentHistory{
                 blocks: recent_blocks
               })
    end

    test "succeeds when entries come from both p_map and recent history", %{
      work_report1: work_report1,
      recent_blocks: recent_blocks
    } do
      # %{hash1 => export1} comes from work_report.specifictions
      # %{hash2 => export2} comes from recent history
      assert :ok ==
               Guarantee.validate_segment_root_lookups([work_report1], %RecentHistory{
                 blocks: recent_blocks
               })
    end
  end
end
