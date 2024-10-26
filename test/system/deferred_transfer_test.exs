defmodule System.DeferredTransferTest do
  use ExUnit.Case
  alias System.DeferredTransfer

  setup_all do
    transfers = [
      %DeferredTransfer{sender: 3, receiver: 1, amount: 100},
      %DeferredTransfer{sender: 1, receiver: 2, amount: 200},
      %DeferredTransfer{sender: 2, receiver: 1, amount: 300},
      %DeferredTransfer{sender: 1, receiver: 1, amount: 400},
      %DeferredTransfer{sender: 2, receiver: 2, amount: 500},
      %DeferredTransfer{sender: 3, receiver: 1, amount: 600},
      %DeferredTransfer{sender: 1, receiver: 1, amount: 700}
    ]

    {:ok, transfers: transfers}
  end

  describe "select_transfers_for_destination/2" do
    test "returns empty list if no transfers target the selected index", %{transfers: transfers} do
      assert DeferredTransfer.select_transfers_for_destination(transfers, 3) == []
    end

    test "sorts transfers by sender first and then by index", %{transfers: transfers} do
      expected = [
        %DeferredTransfer{sender: 1, receiver: 1, amount: 400},
        %DeferredTransfer{sender: 1, receiver: 1, amount: 700},
        %DeferredTransfer{sender: 2, receiver: 1, amount: 300},
        %DeferredTransfer{sender: 3, receiver: 1, amount: 100},
        %DeferredTransfer{sender: 3, receiver: 1, amount: 600}
      ]

      assert DeferredTransfer.select_transfers_for_destination(transfers, 1) == expected
    end

    test "handles empty input list" do
      assert DeferredTransfer.select_transfers_for_destination([], 1) == []
    end

    test "returns correct transfers for a different destination", %{transfers: transfers} do
      expected = [
        %DeferredTransfer{sender: 1, receiver: 2, amount: 200},
        %DeferredTransfer{sender: 2, receiver: 2, amount: 500}
      ]

      assert DeferredTransfer.select_transfers_for_destination(transfers, 2) == expected
    end
  end
end
