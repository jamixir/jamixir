defmodule System.StateTest do
  alias Codec.VariableSize
  alias Codec.NilDiscriminator
  use ExUnit.Case
  import Jamixir.Factory
  import System.State

  setup do
    {:ok,
     %{
       h1: unique_hash_factory(),
       h2: unique_hash_factory(),
       state: build(:genesis_state)
     }}
  end

  describe "state_keys/1" do
    test "authorizer_pool serialization - C(1)", %{h1: h1, h2: h2} do
      state = build(:genesis_state, authorizer_pool: [[h1, h2], [h1]])
      assert state_keys(state)[1] == <<2>> <> h1 <> h2 <> <<1>> <> h1
    end

    test "authorizer_queue serialization - C(2)", %{h1: h1, h2: h2} do
      state = build(:genesis_state, authorizer_queue: [[h1, h2], [h1]])

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
      s = %{state | core_reports: build(:core_reports)}

      expected_to_encode = s.core_reports.reports |> Enum.map(&NilDiscriminator.new/1)

      assert state_keys(s)[10] ==
               Codec.Encoder.encode(expected_to_encode)
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
end
