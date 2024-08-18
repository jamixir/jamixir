defmodule System.StateTest do
  use ExUnit.Case
  import Jamixir.Factory
  import System.State

  setup do
    {:ok, %{h1: unique_hash_factory(), h2: unique_hash_factory()}}
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

    test "recent_history serialization - C(3)" do
      state = build(:genesis_state)
      assert state_keys(state)[3] == Codec.Encoder.encode(state.recent_history)
    end

    test "safrole serialization - C(4)" do
      state = build(:genesis_state)
      assert state_keys(state)[4] == Codec.Encoder.encode(state.safrole)
    end

    test "entropy pool serialization - C(6)" do
      state = build(:genesis_state)
      assert state_keys(state)[6] == Codec.Encoder.encode(state.entropy_pool)
    end
  end
end
