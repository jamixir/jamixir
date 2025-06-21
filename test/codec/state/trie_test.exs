defmodule Codec.State.TrieTest do
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.State.Trie
  import Bitwise
  alias Codec.NilDiscriminator
  alias System.State
  alias System.State.ServiceAccount
  alias Util.Hash
  import Codec.Encoder

  setup_all do
    %{state: state} = build(:genesis_state_with_safrole)

    {:ok, %{state: state, h1: unique_hash_factory(), h2: unique_hash_factory()}}
  end

  # C Constructor
  # Formula (D.1) v0.6.6
  describe "key_to_31_octet" do
    test "convert integer" do
      assert key_to_31_octet(0) == :binary.copy(<<0>>, 31)
      assert key_to_31_octet(7) == <<7>> <> :binary.copy(<<0>>, 30)
      assert key_to_31_octet(255) == <<255>> <> :binary.copy(<<0>>, 30)
    end

    test "convert 255 and service id" do
      assert key_to_31_octet({255, 1}) == <<255>> <> <<1, 0, 0, 0>> <> :binary.copy(<<0>>, 26)

      assert key_to_31_octet({255, 1024}) ==
               <<255>> <> <<0, 0, 4, 0, 0, 0, 0, 0>> <> :binary.copy(<<0>>, 22)

      assert key_to_31_octet({255, 4_294_967_295}) ==
               <<255>> <> <<255, 0, 255, 0, 255, 0, 255, 0>> <> :binary.copy(<<0>>, 22)
    end

    test "error" do
      key =
        {1,
         <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
           0, 0, 3>>}

      a = Hash.default(elem(key, 1))
      a_part = binary_slice(a, 0, 27)
      <<a0, a1, a2, a3, rest::binary>> = a_part

      assert key_to_31_octet(key) == <<1, a0, 0, a1, 0, a2, 0, a3>> <> rest
    end

    test "convert service id and hash" do
      key = "012345678901234567890123456"
      a = Hash.default(key)
      a_part = binary_slice(a, 0, 27)
      <<a0, a1, a2, a3, rest::binary>> = a_part

      # For service id 1
      <<n0_1, n1_1, n2_1, n3_1>> = <<1::32-little>>

      assert key_to_31_octet({1, key}) == <<n0_1, a0, n1_1, a1, n2_1, a2, n3_1, a3>> <> rest

      # For service id 1024
      <<n0_1024, n1_1024, n2_1024, n3_1024>> = <<1024::32-little>>

      assert key_to_31_octet({1024, key}) ==
               <<n0_1024, a0, n1_1024, a1, n2_1024, a2, n3_1024, a3>> <> rest

      # For service id 4_294_967_295
      <<n0_max, n1_max, n2_max, n3_max>> = <<4_294_967_295::32-little>>

      assert key_to_31_octet({4_294_967_295, key}) ==
               <<n0_max, a0, n1_max, a1, n2_max, a2, n3_max, a3>> <> rest
    end

    test "all state keys are encodable with key_to_31_octet", %{state: state} do
      state_keys(state)
      |> Enum.each(fn {k, _} -> assert key_to_31_octet(k) end)
    end
  end

  describe "octet31_to_key" do
    test "convert binary to integer" do
      assert octet31_to_key(:binary.copy(<<0>>, 31)) == 0
      assert octet31_to_key(<<7>> <> :binary.copy(<<0>>, 30)) == 7
      assert octet31_to_key(<<254>> <> :binary.copy(<<0>>, 30)) == 254
    end

    test "convert binary to {integer, service id}" do
      assert octet31_to_key(<<255, 1, 0, 0, 0>> <> :binary.copy(<<0>>, 26)) == {255, 1}

      assert octet31_to_key(<<255, 0, 0, 4, 0>> <> :binary.copy(<<0>>, 26)) == {255, 1024}

      assert octet31_to_key(<<255>> <> <<255, 0, 255, 0, 255, 0, 255>> <> :binary.copy(<<0>>, 23)) ==
               {255, 4_294_967_295}
    end

    test "convert binary to {service id, hash}" do
      hash = "012345678901234567890123456"

      assert octet31_to_key(<<1, "0", 0, "1", 0, "2", 0>> <> "345678901234567890123456") ==
               {1, hash}

      assert octet31_to_key(<<0, "0", 4, "1", 0, "2", 0>> <> "345678901234567890123456") ==
               {1024, hash}

      assert octet31_to_key(<<255, "0", 255, "1", 255, "2", 255>> <> "345678901234567890123456") ==
               {4_294_967_295, hash}
    end
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
          key = {s, <<(1 <<< 32) - 1::32-little>> <> h}
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
          key = {s, <<(1 <<< 32) - 2::32-little>> <> h}
          assert state_keys(state)[key] == v
        end)
      end)
    end

    test "service accounts preimage_storage_l serialization", %{state: state} do
      state.services
      |> Enum.each(fn {s, service_account} ->
        service_account.preimage_storage_l
        |> Enum.each(fn {{h, l}, t} ->
          key = <<l::32-little>> <> h
          value = e(vs(for x <- t, do: <<x::32-little>>))
          assert state_keys(state)[{s, key}] == value
        end)
      end)
    end
  end

  describe "trie_to_state/1" do
    test "trie_to_state/1 smoke", %{state: state} do
      trie_state = %State{
        state
        | services: %{},
          core_reports: [nil, build(:core_report)],
          judgements: build(:judgements),
          accumulation_history:
            for(_ <- 1..(Constants.epoch_length() - 1), do: MapSet.new([Hash.random()])) ++
              [MapSet.new()],
          ready_to_accumulate: build(:ready_to_accumulate)
      }

      recovered_state = serialize(trie_state) |> trie_to_state()

      assert recovered_state.authorizer_pool == trie_state.authorizer_pool
      assert recovered_state.recent_history == trie_state.recent_history
      assert recovered_state.safrole == trie_state.safrole
      assert recovered_state.services == trie_state.services
      assert recovered_state.entropy_pool == trie_state.entropy_pool
      assert recovered_state.next_validators == trie_state.next_validators
      assert recovered_state.curr_validators == trie_state.curr_validators
      assert recovered_state.prev_validators == trie_state.prev_validators
      assert recovered_state.core_reports == trie_state.core_reports
      assert recovered_state.timeslot == trie_state.timeslot
      assert recovered_state.authorizer_queue == trie_state.authorizer_queue
      assert recovered_state.privileged_services == trie_state.privileged_services
      assert recovered_state.judgements == trie_state.judgements
      assert recovered_state.validator_statistics == trie_state.validator_statistics
      assert recovered_state.ready_to_accumulate == trie_state.ready_to_accumulate
      assert recovered_state.accumulation_history == trie_state.accumulation_history

      assert recovered_state == trie_state
    end

    test "trie_to_state/1 - service accounts no storage", %{state: state} do
      trie_state = %State{
        state
        | services: %{
            1_234_567 => %ServiceAccount{
              storage: %{},
              preimage_storage_p: %{},
              preimage_storage_l: %{},
              code_hash: Hash.random(),
              balance: 900,
              gas_limit_g: 90_000,
              gas_limit_m: 20_000_000
            }
          }
      }

      recovered_state = serialize(trie_state) |> trie_to_state()

      assert recovered_state.services == trie_state.services
    end

    test "trie_to_state/1 - service accounts with storage", %{state: state} do
      trie_state = %State{
        state
        | services: %{
            1_234_567 => build(:service_account, storage: %{})
          }
      }

      trie = serialize(trie_state)
      recovered_state = trie_to_state(trie)

      assert recovered_state == trie_state
    end
  end

  describe "fuzzer: encode/decode" do
    test "to -> from binary", %{state: state} do
      assert {:ok, decoded} = from_binary(to_binary(state))
      assert %State{} = trie_to_state(decoded)
      decoded_state = trie_to_state(decoded)
      state_fields = Map.drop(Map.from_struct(state), [:services])

      for {key, value} <- state_fields do
        assert Map.get(decoded_state, key) == value
      end
    end
  end
end
