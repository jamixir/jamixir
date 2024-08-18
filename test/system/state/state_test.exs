defmodule System.StateTest do
  use ExUnit.Case
  import Jamixir.Factory
  import System.State

  setup do
    {:ok, %{h1: unique_hash_factory(), h2: unique_hash_factory()}}
  end

  describe "state_keys/1" do
    test "authorizer_pool serialization - C(1)", %{h1: h1, h2: h2} do
      state = %System.State{authorizer_pool: [[h1, h2], [h1]]}

      assert state_keys(state)[1] == <<2>> <> h1 <> h2 <> h1
    end

    test "authorizer_queue serialization - C(2)", %{h1: h1, h2: h2} do
      state = build(:genesis_state, authorizer_queue: [[h1, h2], [h1]])

      assert state_keys(state)[2] == h1 <> h2 <> h1
    end
  end
end
