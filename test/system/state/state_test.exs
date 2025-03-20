defmodule System.StateTest do
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.State.Trie
  import OriginalModules
  import Mox
  import Bitwise
  alias Codec.State.Json
  alias Block.Extrinsic
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Codec.{NilDiscriminator, JsonEncoder}
  alias IO.ANSI
  alias System.State
  alias Util.Hash
  setup :verify_on_exit!

  setup_all do
    %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)

    {:ok,
     %{
       h1: unique_hash_factory(),
       h2: unique_hash_factory(),
       state: state,
       key_pairs: key_pairs
     }}
  end

  describe "state_keys/1" do
    test "authorizer_pool serialization - C(1)", %{h1: h1, h2: h2} do
      state = %State{authorizer_pool: [[h1, h2], [h1]]}
      assert state_keys(state)[1] == <<2>> <> h1 <> h2 <> <<1>> <> h1
    end

    test "authorizer_queue serialization - C(2)", %{h1: h1, h2: h2} do
      state = %State{authorizer_queue: [[h1, h2], [h1]]}

      assert state_keys(state)[2] == h1 <> h2 <> h1
    end

    test "recent_history serialization - C(3)", %{state: state} do
      assert state_keys(state)[3] == e(state.recent_history)
    end

    test "safrole serialization - C(4)", %{state: state} do
      assert state_keys(state)[4] == e(state.safrole)
    end

    test "judgements serialization - C(5)", %{state: state} do
      assert state_keys(state)[5] == e(state.judgements)
    end

    test "entropy pool serialization - C(6)", %{state: state} do
      assert state_keys(state)[6] == e(state.entropy_pool)
    end

    test "next validators serialization - C(7)", %{state: state} do
      assert state_keys(state)[7] == e(state.next_validators)
    end

    test "next validators serialization - C(8)", %{state: state} do
      assert state_keys(state)[8] == e(state.curr_validators)
    end

    test "previous validators serialization - C(9)", %{state: state} do
      assert state_keys(state)[9] == e(state.prev_validators)
    end

    test "core reports serialization - C(10)", %{state: state} do
      s = %{state | core_reports: build_list(1, :core_report) ++ [nil]}

      expected_to_encode = for c <- s.core_reports, do: NilDiscriminator.new(c)

      assert state_keys(s)[10] == e(expected_to_encode)
    end

    test "timeslot serialization - C(11)", %{state: state} do
      assert state_keys(state)[11] == <<state.timeslot::32-little>>
    end

    test "privileged services serialization - C(12)", %{state: state} do
      assert state_keys(state)[12] == e(state.privileged_services)
    end

    test "validator statistics serialization - C(13)", %{state: state} do
      assert state_keys(state)[13] == e(state.validator_statistics)
    end

    test "validator accumulation history serialization - C(14)", %{state: state} do
      assert state_keys(state)[14] == e(for a <- state.accumulation_history, do: vs(a))
    end

    test "validator ready to accumulate serialization - C(15)", %{state: state} do
      assert state_keys(state)[15] == e(for a <- state.ready_to_accumulate, do: vs(a))
    end

    test "service accounts storage serialization", %{state: state} do
      # Test storage encoding (2^32 - 1 prefix)
      state.services
      |> Enum.each(fn {s, service_account} ->
        Map.get(service_account, :storage)
        |> Enum.each(fn {h, v} ->
          key = {s, <<(1 <<< 32) - 1::32-little>> <> binary_slice(h, 0, 28)}
          assert state_keys(state)[key] == v
        end)
      end)
    end

    test "service accounts preimage_storage_p serialization", %{state: state} do
      # Test preimage storage encoding (2^32 - 2 prefix)
      state.services
      |> Enum.each(fn {s, service_account} ->
        Map.get(service_account, :preimage_storage_p)
        |> Enum.each(fn {h, v} ->
          key = {s, <<(1 <<< 32) - 2::32-little>> <> binary_slice(h, 1, 28)}
          assert state_keys(state)[key] == v
        end)
      end)
    end

    test "service accounts preimage_storage_l serialization", %{state: state} do
      state.services
      |> Enum.each(fn {s, service_account} ->
        service_account.preimage_storage_l
        |> Enum.each(fn {{h, l}, t} ->
          key = <<l::32-little>> <> (Hash.default(h) |> binary_slice(2, 28))
          value = e(vs(for x <- t, do: <<x::32-little>>))
          assert state_keys(state)[{s, key}] == value
        end)
      end)
    end
  end

  # C Constructor
  # Formula (D.1) v0.6.0
  describe "key_to_32_octet" do
    test "convert integer" do
      assert key_to_32_octet(0) == :binary.copy(<<0>>, 32)
      assert key_to_32_octet(7) == <<7>> <> :binary.copy(<<0>>, 31)
      assert key_to_32_octet(255) == <<255>> <> :binary.copy(<<0>>, 31)
    end

    test "convert 255 and service id" do
      assert key_to_32_octet({255, 1}) == <<255>> <> <<1, 0, 0, 0>> <> :binary.copy(<<0>>, 27)

      assert key_to_32_octet({255, 1024}) ==
               <<255>> <> <<0, 0, 4, 0, 0, 0, 0, 0>> <> :binary.copy(<<0>>, 23)

      assert key_to_32_octet({255, 4_294_967_295}) ==
               <<255>> <> <<255, 0, 255, 0, 255, 0, 255, 0>> <> :binary.copy(<<0>>, 23)
    end

    test "error" do
      key =
        {1,
         <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
           0, 0, 3>>}

      assert key_to_32_octet(key) == <<1, 0, 0, 0>> <> :binary.copy(<<0>>, 28)
    end

    test "convert service id and hash" do
      hash = "01234567890123456789012345678901"

      assert key_to_32_octet({1, hash}) ==
               <<1>> <>
                 "0" <> <<0>> <> "1" <> <<0>> <> "2" <> <<0>> <> "3456789012345678901234567"

      assert key_to_32_octet({1024, hash}) ==
               <<0>> <>
                 "0" <> <<4>> <> "1" <> <<0>> <> "2" <> <<0>> <> "3456789012345678901234567"

      assert key_to_32_octet({4_294_967_295, hash}) ==
               <<255>> <>
                 "0" <> <<255>> <> "1" <> <<255>> <> "2" <> <<255>> <> "3456789012345678901234567"
    end

    test "all state keys are encodable with key_to_32_octet", %{state: state} do
      state_keys(state)
      |> Enum.each(fn {k, _} -> assert key_to_32_octet(k) end)
    end
  end

  describe "serialize/1" do
    test "serialized state dictionary", %{state: state} do
      state_keys = state_keys(state)
      serialized_state = serialize(state)

      state_keys
      |> Enum.each(fn {k, _} ->
        assert Map.get(state_keys, k) == Map.get(serialized_state, key_to_32_octet(k))
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

      ValidatorStatisticsMock
      |> expect(:do_transition, 1, fn _, _, _, _, _, _, _ ->
        {:ok, "mockvalue"}
      end)

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
      state = %{state | core_reports: [core_report]}

      extrinsic =
        build(
          :extrinsic,
          assurances: [build(:assurance, validator_index: 0, bitfield: <<0b1111::8>>)]
        )

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
      genesis_json = File.read!("genesis/genesis.json") |> Jason.decode!() |> Utils.atomize_keys()

      assert JsonEncoder.encode(Json.decode(genesis_json)) == genesis_json
    end

    @tag :skip
    # genesis DOES NOT match key vals after remove the hardcoded values
    # solve by
    # a. use our own genesis
    # b. have jam duna correctly encode service account
    test "genesis matches key vals" do
      {:ok, state} = Codec.State.from_genesis()
      {:ok, content} = File.read("test/genesis-keyvals.json")
      {:ok, json} = Jason.decode(content)
      state_hex = Codec.State.Trie.serialize_hex(state)

      for [k, v] <- json["keyvals"] do
        my_k = String.replace(k, "0x", "") |> String.upcase()
        my_v = String.replace(v, "0x", "") |> String.upcase()

        if state_hex[my_k] == my_v do
          # IO.puts("#{ANSI.green()} #{my_k} => #{my_v}\n")
        else
          IO.puts("#{ANSI.red()}> #{my_k} => #{my_v}")
          IO.puts("#{ANSI.red()}< #{state_hex[my_k]}\n")
          assert state_hex[my_k] == my_v
        end
      end
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
