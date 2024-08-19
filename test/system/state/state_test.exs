defmodule System.StateTest do
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

      assert state_keys(state)[1] == <<2>> <> h1 <> h2 <> h1
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

    test "timeslot serialization - C(11)", %{state: state} do
      assert state_keys(state)[11] == Codec.Encoder.encode_le(state.timeslot, 4)
    end
  end
end
