defmodule System.State.ServiceAccountTest do
  alias System.State.ServiceAccount
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, %{sa: build(:service_account), preimage: :crypto.strong_rand_bytes(32)}}
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
      assert ServiceAccount.octets_in_storage(sa) == 117
    end

    test "empty items in storage", %{sa: sa} do
      assert ServiceAccount.octets_in_storage(%{sa | storage: %{}}) == 81
    end

    test "empty items in preimage storage l", %{sa: sa} do
      assert ServiceAccount.octets_in_storage(%{sa | preimage_storage_l: %{}}) == 36
    end
  end

  describe "code/1" do
    test "return nil value when code does not exist", %{sa: sa} do
      assert ServiceAccount.code(sa) == nil
    end

    test "return code when it exists in preimage storage p", %{sa: sa} do
      code_hash = :crypto.strong_rand_bytes(32)

      assert ServiceAccount.code(%{
               sa
               | code_hash: code_hash,
                 preimage_storage_p: %{code_hash => <<1, 2, 3>>}
             }) == <<1, 2, 3>>
    end
  end

  describe "store_preimage/3" do
    test "store preimage in preimage storage", %{sa: sa, preimage: preimage} do
      expected_hash = Util.Hash.default(preimage)

      p_key_count = Map.keys(sa.preimage_storage_p) |> length()
      l_key_count = Map.keys(sa.preimage_storage_l) |> length()

      sa = ServiceAccount.store_preimage(sa, preimage, 1)

      assert sa |> Map.get(:preimage_storage_p) |> Map.get(expected_hash) == preimage

      assert sa |> Map.get(:preimage_storage_l) |> Map.get({expected_hash, byte_size(preimage)}) ==
               [1]

      assert Map.keys(sa.preimage_storage_p) |> length() == p_key_count + 1
      assert Map.keys(sa.preimage_storage_l) |> length() == l_key_count + 1
    end
  end

  # Formula (94) v0.3.4
  describe "historical_lookup/3" do
    test "return nil when historical lookup does not exist", %{sa: sa} do
      assert ServiceAccount.historical_lookup(sa, 1, :crypto.strong_rand_bytes(32)) == nil
    end

    # case when x <= t
    test "return correct value when historical lookup does exist", %{sa: sa, preimage: preimage} do
      expected_hash = Util.Hash.default(preimage)

      sa = ServiceAccount.store_preimage(sa, preimage, 1)

      assert ServiceAccount.historical_lookup(sa, 1, expected_hash) == preimage
    end

    # case when x > t
    test "return nil when it is not available yet", %{sa: sa, preimage: preimage} do
      expected_hash = Util.Hash.default(preimage)

      sa = ServiceAccount.store_preimage(sa, preimage, 10)

      assert ServiceAccount.historical_lookup(sa, 1, expected_hash) == nil
    end

    test "marked as unavailable ", %{sa: sa, preimage: preimage} do
      expected_hash = Util.Hash.default(preimage)
      sa = ServiceAccount.store_preimage(sa, preimage, 10)
      sa = sa |> Map.put(:preimage_storage_l, %{{expected_hash, byte_size(preimage)} => [10, 20]})

      # case t >= x and t < y
      assert ServiceAccount.historical_lookup(sa, 15, expected_hash) == preimage
      # case t >= x and t >= y
      assert ServiceAccount.historical_lookup(sa, 20, expected_hash) == nil
    end

    test "marked as available again", %{sa: sa, preimage: preimage} do
      expected_hash = Util.Hash.default(preimage)
      sa = ServiceAccount.store_preimage(sa, preimage, 10)

      sa =
        sa
        |> Map.put(:preimage_storage_l, %{{expected_hash, byte_size(preimage)} => [10, 20, 30]})

      # case t >= x and t < y
      assert ServiceAccount.historical_lookup(sa, 15, expected_hash) == preimage
      # case t >= x and t >= y
      assert ServiceAccount.historical_lookup(sa, 29, expected_hash) == nil
      # case t >= z
      assert ServiceAccount.historical_lookup(sa, 30, expected_hash) == preimage
    end
  end

  describe "threshold balance" do
    test "return correct value for threshold balance", %{sa: sa} do
      assert ServiceAccount.threshold_balance(sa) == 247
    end
  end

  describe "encode/1" do
    test "encode service account smoke test" do
      assert Codec.Encoder.encode(build(:service_account)) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\xE8\x03\0\0\0\0\0\0\x88\x13\0\0\0\0\0\0\x10'\0\0\0\0\0\0u\0\0\0\0\0\0\0\x03\0\0\0"
    end
  end
end
