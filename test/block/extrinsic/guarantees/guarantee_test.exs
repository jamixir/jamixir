defmodule Block.Extrinsic.GuaranteeTest do
  use ExUnit.Case
  import Jamixir.Factory

  alias Block.Extrinsic.{Guarantee, Guarantor}
  alias System.State
  alias Util.{Crypto, Hash}

  defmodule GuaranteeConstantsMock do
    def validator_count, do: 6
    def core_count, do: 2
    def rotation_period, do: 10
  end

  describe "validate/1" do
    setup do
      valid_guarantee1 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 1),
          timeslot: 100,
          credentials: [{1, <<3::512>>}, {2, <<4::512>>}]
        )

      valid_guarantee2 =
        build(:guarantee,
          work_report: build(:work_report, core_index: 2),
          timeslot: 100,
          credentials: [{1, <<1::512>>}, {2, <<2::512>>}]
        )

      {:ok, valid_guarantee1: valid_guarantee1, valid_guarantee2: valid_guarantee2}
    end

    test "returns :ok for valid guarantees", context do
      assert Guarantee.validate([context.valid_guarantee1, context.valid_guarantee2], %State{}, 1) ==
               :ok
    end

    test "returns error for guarantees not ordered by core_index", context do
      assert Guarantee.validate([context.valid_guarantee2, context.valid_guarantee1], %State{}, 1) ==
               {:error, :not_in_order}
    end

    test "returns error for duplicate core_index in guarantees", context do
      assert Guarantee.validate([context.valid_guarantee1, context.valid_guarantee1], %State{}, 1) ==
               {:error, :duplicates}
    end

    test "returns error for invalid credential length", context do
      assert Guarantee.validate(
               [%Guarantee{context.valid_guarantee1 | credentials: [{1, <<1::512>>}]}],
               %State{},
               1
             ) == {:error, "Invalid credentials in one or more guarantees"}
    end

    test "returns error for credentials not ordered by validator_index", context do
      assert Guarantee.validate(
               [
                 %Guarantee{
                   context.valid_guarantee1
                   | credentials: [{2, <<1::512>>}, {1, <<2::512>>}]
                 }
               ],
               %State{},
               1
             ) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "returns error for duplicate validator_index in credentials", context do
      assert Guarantee.validate(
               [
                 %Guarantee{
                   context.valid_guarantee1
                   | credentials: [{1, <<1::512>>}, {1, <<2::512>>}]
                 }
               ],
               %State{},
               1
             ) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "handles empty list of guarantees" do
      assert Guarantee.validate([], %State{}, 1) == :ok
    end

    test "validates a single guarantee correctly", context do
      assert Guarantee.validate([context.valid_guarantee1], %State{}, 1) == :ok
    end

    test "returns error when gas accumulation exceeds limit" do
      work_results = [
        build(:work_result, service_index: 0),
        build(:work_result, service_index: 1)
      ]

      guarantees = [
        build(:guarantee,
          work_report: build(:work_report, core_index: 0, work_results: work_results)
        ),
        build(:guarantee,
          work_report: build(:work_report, core_index: 1, work_results: work_results)
        )
      ]

      # sum of 4 work results can't be bigger than 1_000
      state = %State{services: %{0 => %{gas_limit_g: 250}, 1 => %{gas_limit_g: 249}}}
      assert Guarantee.validate(guarantees, state, 1) == :ok

      state = %State{services: %{0 => %{gas_limit_g: 250}, 1 => %{gas_limit_g: 251}}}
      assert Guarantee.validate(guarantees, state, 1) == {:error, :invalid_gas_accumulation}
    end

    test "returns error when duplicated work package hash", %{
      valid_guarantee1: g1,
      valid_guarantee2: g2
    } do
      new_spec = %{
        g2.work_report.specification
        | work_package_hash: g1.work_report.specification.work_package_hash
      }

      guarantees = [g1, %{g2 | work_report: %{g2.work_report | specification: new_spec}}]

      assert Guarantee.validate(guarantees, %State{}, 1) ==
               {:error, :duplicated_wp_hash}
    end

    test "returns error when refinement context timeslot is too old", context do
      current_timeslot = 1000
      old_timeslot = current_timeslot - Constants.max_age_lookup_anchor() - 1

      guarantee_with_old_context = %{
        context.valid_guarantee1
        | work_report: %{
            context.valid_guarantee1.work_report
            | refinement_context: %{
                context.valid_guarantee1.work_report.refinement_context
                | timeslot: old_timeslot
              }
          }
      }

      assert Guarantee.validate([guarantee_with_old_context], %State{}, current_timeslot) ==
               {:error, :refine_context_timeslot}
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
end
