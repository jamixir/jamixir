defmodule System.State.RecentBlockTest do
  use ExUnit.Case

  alias System.State.RecentBlock
  alias Block.Header

  test "get_initial_block_history/2 returns empty list when given nil" do
    header = %Header{prior_state_root: "s"}
    assert RecentBlock.get_initial_block_history(header, nil) === []
  end

  test "get_initial_block_history/2 returns empty list when given empty list" do
    header = %Header{prior_state_root: "s"}
    assert RecentBlock.get_initial_block_history(header, []) === []
  end

  test "get_initial_block_history/2 returns list with modified first block when given non-empty list" do
    header = %Header{prior_state_root: "s"}
    most_recent_block1 = %RecentBlock{state_root: nil}
    most_recent_block2 = %RecentBlock{state_root: "s2"}
    block_history = [most_recent_block1, most_recent_block2]
    expected = [%RecentBlock{state_root: "s"}, most_recent_block2]
    assert RecentBlock.get_initial_block_history(header, block_history) === expected
  end
end
