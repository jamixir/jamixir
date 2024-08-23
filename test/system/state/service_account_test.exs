defmodule System.State.ServiceAccountTest do
  alias System.State.ServiceAccount
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, %{sa: build(:service_account)}}
  end

  describe "items in storage" do
    test "return correct value for itens in storage", %{sa: sa} do
      assert ServiceAccount.items_in_storage(sa) == 3
    end

    test "empty items in storage", %{sa: sa} do
      assert ServiceAccount.items_in_storage(%{sa | storage: %{}}) == 2
    end

    test "empty items in preimage storage l", %{sa: sa} do
      assert ServiceAccount.items_in_storage(%{sa | preimage_storage_l: %{}}) == 1
    end
  end

  describe "octets in storage" do
    test "return correct value for octets in storage", %{sa: sa} do
      assert ServiceAccount.octets_in_storage(sa) == 0
    end
  end

  describe "encode/1" do
    test "encode service account smoke test" do
      assert Codec.Encoder.encode(build(:service_account)) ==
               ""
    end
  end
end
