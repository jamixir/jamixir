defmodule System.StateTest do
  use ExUnit.Case
  import Jamixir.Factory
  import System.State
  import Mox
  alias Codec.NilDiscriminator
  alias Codec.VariableSize
  alias System.State
  alias System.State.ValidatorStatistics
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
      assert state_keys(state)[3] == Codec.Encoder.encode(state.recent_history)
    end

    test "safrole serialization - C(4)", %{state: state} do
      assert state_keys(state)[4] == Codec.Encoder.encode(state.safrole)
    end

    test "judgements serialization - C(5)", %{state: state} do
      assert state_keys(state)[5] == Codec.Encoder.encode(state.judgements)
    end

    test "entropy pool serialization - C(6)", %{state: state} do
      assert state_keys(state)[6] == Codec.Encoder.encode(state.entropy_pool)
    end

    test "next validators serialization - C(7)", %{state: state} do
      assert state_keys(state)[7] == Codec.Encoder.encode(state.next_validators)
    end

    test "next validators serialization - C(8)", %{state: state} do
      assert state_keys(state)[8] == Codec.Encoder.encode(state.curr_validators)
    end

    test "previous validators serialization - C(9)", %{state: state} do
      assert state_keys(state)[9] == Codec.Encoder.encode(state.prev_validators)
    end

    test "core reports serialization - C(10)", %{state: state} do
      s = %{state | core_reports: build_list(1, :core_report) ++ [nil]}

      expected_to_encode = s.core_reports |> Enum.map(&NilDiscriminator.new/1)

      assert state_keys(s)[10] == Codec.Encoder.encode(expected_to_encode)
    end

    test "timeslot serialization - C(11)", %{state: state} do
      assert state_keys(state)[11] == Codec.Encoder.encode_le(state.timeslot, 4)
    end

    test "privileged services serialization - C(12)", %{state: state} do
      assert state_keys(state)[12] == Codec.Encoder.encode(state.privileged_services)
    end

    test "validator statistics serialization - C(13)", %{state: state} do
      assert state_keys(state)[13] == Codec.Encoder.encode(state.validator_statistics)
    end

    test "service accounts serialization", %{state: state} do
      assert state_keys(state)[{255, 1}] == Codec.Encoder.encode(state.services[1])

      [:storage, :preimage_storage_p]
      |> Enum.each(fn proprety ->
        state.services
        |> Enum.each(fn {s, service_account} ->
          Map.get(service_account, proprety)
          |> Enum.each(fn {h, v} -> assert state_keys(state)[{s, h}] == v end)
        end)
      end)
    end

    test "service accounts preimage_storage_l serialization", %{state: state} do
      state.services
      |> Enum.each(fn {s, service_account} ->
        service_account.preimage_storage_l
        |> Enum.each(fn {{h, l}, t} ->
          <<_::binary-size(4), rest::binary>> = h
          key = Codec.Encoder.encode_le(l, 4) <> rest

          value =
            Codec.Encoder.encode(VariableSize.new(t |> Enum.map(&Codec.Encoder.encode_le(&1, 4))))

          assert state_keys(state)[{s, key}] == value
        end)
      end)
    end
  end

  # C Constructor
  # Formula (291) v0.3.4
  describe "key_to_32_octet" do
    test "convert integer" do
      assert key_to_32_octet(0) == :binary.copy(<<0>>, 32)
      assert key_to_32_octet(7) == <<7>> <> :binary.copy(<<0>>, 31)
      assert key_to_32_octet(255) == <<255>> <> :binary.copy(<<0>>, 31)
    end

    test "convert 255 and service id" do
      assert key_to_32_octet({255, 1}) == <<255>> <> <<1, 0, 0, 0>> <> :binary.copy(<<0>>, 27)
      assert key_to_32_octet({255, 1024}) == <<255>> <> <<0, 4, 0, 0>> <> :binary.copy(<<0>>, 27)

      assert key_to_32_octet({255, 4_294_967_295}) ==
               <<255>> <> <<255, 255, 255, 255>> <> :binary.copy(<<0>>, 27)
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
    test "add block smoke test", %{state: state, key_pairs: key_pairs} do
      State.add_block(state, build(:safrole_block, state: state, key_pairs: key_pairs))
    end

    test "updates statistics", %{state: state, key_pairs: key_pairs} do
      Application.put_env(:jamixir, :validator_statistics, ValidatorStatisticsMock)

      on_exit(fn ->
        # Reset to the actual implementation after the test
        Application.put_env(:jamixir, :validator_statistics, ValidatorStatistics)
      end)

      ValidatorStatisticsMock
      |> expect(:posterior_validator_statistics, 1, fn _, _, _, _, _ -> "mockvalue" end)

      new_state =
        State.add_block(state, build(:safrole_block, state: state, key_pairs: key_pairs))

      assert new_state.validator_statistics == "mockvalue"
    end
  end

  describe "from_json/1" do
    test "from_json smoke test" do
      # state =
      #   assert State.from_json(json) == state
    end
  end
end
