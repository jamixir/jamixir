defmodule System.StateTest do
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.State.Trie
  import OriginalModules
  import Mox
  import TestHelper
  alias Block.Extrinsic
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.JsonEncoder
  alias Codec.State.Json
  alias System.State
  alias Util.Hash
  setup :verify_on_exit!

  setup_all do
    %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)

    {:ok, %{state: state, key_pairs: key_pairs}}
  end

  describe "serialize/1" do
    test "serialized state dictionary", %{state: state} do
      state_keys = state_keys(state)
      serialized_state = serialize(state) |> Map.get(:data)

      state_keys
      |> Enum.each(fn {k, _} ->
        assert Map.get(state_keys, k) == Map.get(serialized_state, key_to_31_octet(k))
      end)
    end
  end

  describe "add_block/2" do
    setup do
      Application.put_env(:jamixir, :original_modules, [])

      on_exit(fn ->
        Application.delete_env(:jamixir, :original_modules)
      end)

      :ok
    end

    test "add block smoke test", %{state: state, key_pairs: key_pairs} do
      State.add_block(state, build(:safrole_block, state: state, key_pairs: key_pairs))
    end

    test "updates statistics", %{state: state, key_pairs: key_pairs} do
      Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

      on_exit(fn ->
        # Reset to the actual implementation after the test
        Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      end)

      mock_statistics()

      {:ok, state_} =
        State.add_block(state, build(:safrole_block, state: state, key_pairs: key_pairs))

      assert state_.validator_statistics == "mockvalue"
    end

    test "don't updates statistics when error", %{state: state, key_pairs: key_pairs} do
      Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

      on_exit(fn ->
        # Reset to the actual implementation after the test
        Application.put_env(:jamixir, :validator_statistics, System.State.ValidatorStatistics)
      end)

      ValidatorStatisticsMock
      |> expect(:do_transition, 1, fn _, _, _, _, _, _, _ ->
        {:error, "message"}
      end)

      {:error, state_, _} =
        State.add_block(state, build(:safrole_block, state: state, key_pairs: key_pairs))

      assert state_.validator_statistics == state.validator_statistics
    end

    test "state transition with core report update", %{state: state, key_pairs: key_pairs} do
      with_original_modules([:transition]) do
        new_core_report = build(:core_report)
        state = %{state | core_reports: [new_core_report | tl(state.core_reports)]}
        state = put_in(state.services, %{0 => build(:service_account)})

        {:ok, new_state} =
          State.add_block(
            state,
            build(:safrole_block, state: state, key_pairs: key_pairs, extrinsic: %Extrinsic{})
          )

        assert hd(new_state.core_reports) == new_core_report
        assert tl(new_state.core_reports) == tl(state.core_reports)
      end
    end

    test "state transition filter out available reports", %{state: state, key_pairs: key_pairs} do
      core_report = build(:core_report, work_report: %WorkReport{core_index: 0})
      state = %{state | core_reports: [core_report, nil]}

      extrinsic = build(:extrinsic, guarantees: [])

      with_original_modules([:process_availability]) do
        {:ok, new_state} =
          State.add_block(
            state,
            build(:safrole_block,
              state: state,
              key_pairs: key_pairs,
              extrinsic: extrinsic
            )
          )

        assert Enum.all?(new_state.core_reports, &(&1 == nil))
      end
    end
  end

  describe "validations fails" do
    test "returns error when assurance validation fails", %{state: state} do
      with_original_modules([:validate_assurances]) do
        # Invalid assurance hash
        invalid_extrinsic = build(:extrinsic, assurances: [build(:assurance)])

        invalid_block = %Block{
          header: build(:header, timeslot: 100),
          extrinsic: invalid_extrinsic
        }

        assert {:error, _, :bad_attestation_parent} = State.add_block(state, invalid_block)
      end
    end

    test "returns error when epoch marker validation fails", %{state: state} do
      with_original_modules([:valid_epoch_marker]) do
        # Invalid epoch marker, on a new epoch epoch marker should be nil
        invalid_block = %Block{
          header: build(:header, timeslot: 600, epoch_mark: {Hash.one(), [Hash.two()]}),
          extrinsic: build(:extrinsic)
        }

        assert {:error, _, "Invalid epoch marker"} = State.add_block(state, invalid_block)
      end
    end
  end

  describe "from_genesis/0" do
    test "from_genesis smoke test" do
      {:ok, state} = Codec.State.from_genesis()
      assert state.timeslot == 0
    end

    test "decode/encode genesis state" do
      genesis_json = JsonReader.read("genesis/genesis.json")
      assert JsonEncoder.encode(Json.decode(genesis_json)) == genesis_json
    end
  end

  describe "to_json/1" do
    test "encodes services map correctly" do
      s1 = build(:service_account)
      s2 = build(:service_account)

      state = %State{
        services: %{
          1 => s1,
          2 => s2
        },
        ready_to_accumulate: build(:ready_to_accumulate),
        accumulation_history: build(:accumulation_history)
      }

      json = JsonEncoder.encode(state)

      assert json.delta == [
               %{
                 id: 1,
                 data: JsonEncoder.encode(s1)
               },
               %{
                 id: 2,
                 data: JsonEncoder.encode(s2)
               }
             ]

      assert json.theta == for(r <- state.ready_to_accumulate, do: JsonEncoder.encode(r))
      assert json.xi == for(h <- state.accumulation_history, do: JsonEncoder.encode(h))
    end
  end
end
