defmodule NodeCLIServerTest do
  use ExUnit.Case, async: true
  import Jamixir.Factory
  import Jamixir.NodeCLIServer

  describe "validator index and assigned shards  " do
    setup do
      KeyManager.load_keys("test/keys/4.json")
      s = build(:genesis_state)
      start_link(jam_state: s)

      {:ok, state: s}
    end

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

  defp assign_me_to_index(state, index) do
    v = state.curr_validators |> Enum.at(index)
    v = put_in(v.ed25519, KeyManager.get_our_ed25519_key())
    new_curr = List.replace_at(state.curr_validators, index, v)
    s = put_in(state.curr_validators, new_curr)
    set_jam_state(s)
  end
end
