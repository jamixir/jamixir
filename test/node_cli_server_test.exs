defmodule NodeCLIServerTest do
  alias System.State.Validator
  use ExUnit.Case, async: true
  import Jamixir.Factory
  import Jamixir.NodeCLIServer

  setup do
    KeyManager.load_keys("test/keys/4.json")
    s = build(:genesis_state)
    start_link(jam_state: s)

    {:ok, state: s}
  end

  describe "validator index and assigned shards  " do
    test "returns nil no state found" do
      assert validator_index() == nil
    end

    test "returns nil when no index found" do
      assert validator_index() == nil
    end

    test "returns correct index", %{state: state} do
      assign_me_to_index(state, 3)
      assert validator_index() == 3
    end

    test "returns nil when not in validators list shard index" do
      assert assigned_shard_index(2) == nil
    end

    # i = (cR + v) mod V
    test "returns correct shard index", %{state: state} do
      assign_me_to_index(state, 2)
      # i = (1 * 2 + 2) mod 6 = 4
      assert assigned_shard_index(1) == 4
      # i = (0 * 2 + 2) mod 6 = 2
      assert assigned_shard_index(0) == 2
    end

    test "returns correct shard index overflow division", %{state: state} do
      assign_me_to_index(state, 5)
      # i = (1 * 2 + 5) mod 6 = 1
      assert assigned_shard_index(1) == 1
    end
  end

  describe "guarantors/0" do
    test "correctly return guarantors" do
      guarantors = guarantors()
      assert Enum.sort(guarantors.assigned_cores) == [0, 0, 0, 1, 1, 1]
      assert length(Enum.sort(guarantors.validators)) == 6
      [%Validator{} | _] = guarantors.validators
    end
  end

  describe "assigned_core/0" do
    test "returns assigned core for current validator", %{state: state} do
      assign_me_to_index(state, 1)
      assert assigned_core() in [0, 1]
    end

    test "returns nil when not a validator" do
      assert assigned_core() == nil
    end
  end

  describe "guarantors_same_core/0" do
    test "return other 2 guarantors in the same core", %{state: state} do
      assign_me_to_index(state, 1)
      guarantors = same_core_guarantors()
      assert length(guarantors) == 2

      assert Enum.find(guarantors, fn v -> v.ed25519 == KeyManager.get_our_ed25519_key() end) ==
               nil
    end
  end

  defp assign_me_to_index(state, index) do
    v = state.curr_validators |> Enum.at(index)
    v = put_in(v.ed25519, KeyManager.get_our_ed25519_key())
    new_curr = List.replace_at(state.curr_validators, index, v)
    s = put_in(state.curr_validators, new_curr)
    set_jam_state(s)
  end
end
