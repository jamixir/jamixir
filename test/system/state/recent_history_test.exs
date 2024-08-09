defmodule System.State.RecentHistoryTest do
  use ExUnit.Case

  alias System.State.RecentHistory
  alias System.State.RecentHistory.RecentBlock
  alias Block.Header

  test "update_latest_posterior_state_root/2 returns empty list when given nil" do
    header = %Header{prior_state_root: "s"}
    assert RecentHistory.update_latest_posterior_state_root(nil, header).blocks === []
  end

  test "update_latest_posterior_state_root/2 returns empty list when given empty list" do
    header = %Header{prior_state_root: "s"}

    assert RecentHistory.update_latest_posterior_state_root(RecentHistory.new(), header).blocks ===
             []
  end

  test "update_latest_posterior_state_root/2 returns list with modified first block when given non-empty list" do
    header = %Header{prior_state_root: "s"}
    most_recent_block1 = %RecentBlock{state_root: nil}
    most_recent_block2 = %RecentBlock{state_root: "s2"}

    block_history =
      RecentHistory.new()
      |> RecentHistory.add(most_recent_block1)
      |> RecentHistory.add(most_recent_block2)

    expected = [most_recent_block1, %RecentBlock{state_root: "s"}]
    assert RecentHistory.update_latest_posterior_state_root(block_history, header).blocks === expected
  end
end
