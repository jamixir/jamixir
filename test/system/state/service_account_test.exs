defmodule System.State.ServiceAccountTest do
  alias System.State.ServiceAccount
  alias Util.Hash
  use ExUnit.Case
  import Codec.Encoder
  import Jamixir.Factory
  alias Codec.JsonEncoder

  setup do
    {:ok, %{sa: build(:service_account), preimage: Hash.random()}}
  end

  describe "items in storage" do
    test "return correct value for itens in storage", %{sa: sa} do
      assert ServiceAccount.items_in_storage(sa) == 3
    end

    test "empty items in storage", %{sa: sa} do
      assert ServiceAccount.items_in_storage(%{sa | storage: HashedKeysMap.new(%{})}) == 2
    end

    test "empty items in preimage storage l", %{sa: sa} do
      assert ServiceAccount.items_in_storage(%{sa | preimage_storage_l: %{}}) == 1
    end
  end

  describe "octets in storage" do
    test "return correct value for octets in storage", %{sa: sa} do
      # 81 + bytes size of single item in preimage_l + 34+ byte_size(key) + byte_size(value) of single item in storage
      assert ServiceAccount.octets_in_storage(sa) == 81 + 4 + 34 + 32 + 4
    end

    test "empty items in storage", %{sa: sa} do
      assert ServiceAccount.octets_in_storage(%{sa | storage: HashedKeysMap.new(%{})}) == 85
    end

    test "empty items in preimage storage l", %{sa: sa} do
      assert ServiceAccount.octets_in_storage(%{sa | preimage_storage_l: %{}}) == 34 + 32 + 4
    end
  end

  describe "code/1" do
    test "return nil value when code does not exist", %{sa: sa} do
      assert ServiceAccount.code(%{sa | code_hash: Hash.four()}) == nil
    end

    test "return code when it exists in preimage storage p", %{sa: sa} do
      code_hash = Hash.random()
      service = %{sa | code_hash: code_hash, preimage_storage_p: %{code_hash => <<0, 1, 2, 3>>}}
      assert ServiceAccount.code(service) == <<1, 2, 3>>
    end

    test "return empty metadata and code", %{sa: sa} do
      code_hash = Hash.random()
      service = %{sa | code_hash: code_hash, preimage_storage_p: %{code_hash => <<0>>}}
      assert ServiceAccount.metadata(service) == <<>>
      assert ServiceAccount.code(service) == <<>>
    end

    test "metadata and code", %{sa: sa} do
      hash = Hash.random()

      service = %{sa | code_hash: hash, preimage_storage_p: %{hash => <<1, 1, 2, 3, 4>>}}

      assert ServiceAccount.metadata(service) == <<1>>
      assert ServiceAccount.code(service) == <<2, 3, 4>>
    end
  end

  describe "store_preimage/3" do
    test "store preimage in preimage storage", %{sa: sa, preimage: preimage} do
      expected_hash = h(preimage)

      p_key_count = Map.keys(sa.preimage_storage_p) |> length()
      l_key_count = Map.keys(sa.preimage_storage_l) |> length()

      sa = ServiceAccount.store_preimage(sa, preimage, 1)

      assert sa.preimage_storage_p[expected_hash] == preimage
      assert sa.preimage_storage_l[{expected_hash, byte_size(preimage)}] == [1]

      assert Map.keys(sa.preimage_storage_p) |> length() == p_key_count + 1
      assert Map.keys(sa.preimage_storage_l) |> length() == l_key_count + 1
    end
  end

  # Formula (9.7) v0.6.6
  describe "historical_lookup/3" do
    test "return nil when historical lookup does not exist", %{sa: sa} do
      assert ServiceAccount.historical_lookup(sa, 1, Hash.random()) == nil
    end

    # case when x <= t
    test "return correct value when historical lookup does exist", %{sa: sa, preimage: preimage} do
      expected_hash = h(preimage)

      sa = ServiceAccount.store_preimage(sa, preimage, 1)

      assert ServiceAccount.historical_lookup(sa, 1, expected_hash) == preimage
    end

    # case when x > t
    test "return nil when it is not available yet", %{sa: sa, preimage: preimage} do
      expected_hash = h(preimage)

      sa = ServiceAccount.store_preimage(sa, preimage, 10)

      assert ServiceAccount.historical_lookup(sa, 1, expected_hash) == nil
    end

    test "marked as unavailable ", %{sa: sa, preimage: preimage} do
      expected_hash = h(preimage)
      sa = ServiceAccount.store_preimage(sa, preimage, 10)
      sa = sa |> Map.put(:preimage_storage_l, %{{expected_hash, byte_size(preimage)} => [10, 20]})

      # case t >= x and t < y
      assert ServiceAccount.historical_lookup(sa, 15, expected_hash) == preimage
      # case t >= x and t >= y
      assert ServiceAccount.historical_lookup(sa, 20, expected_hash) == nil

      # case in_storage?([], _)
      sa = sa |> Map.put(:preimage_storage_l, %{{expected_hash, byte_size(preimage)} => []})
      assert ServiceAccount.historical_lookup(sa, 20, expected_hash) == nil

      # case in_storage?(nil, _)
      sa = sa |> Map.put(:preimage_storage_l, %{})
      assert ServiceAccount.historical_lookup(sa, 20, expected_hash) == nil
    end

    test "marked as available again", %{sa: sa, preimage: preimage} do
      expected_hash = h(preimage)
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
      items_in_storage = 3
      octets_in_storage = 81 + 4 + 34 + 32 + 4
      deposit_offset = 40

      assert ServiceAccount.threshold_balance(sa) ==
               Constants.service_minimum_balance() +
                 Constants.additional_minimum_balance_per_item() * items_in_storage +
                 Constants.additional_minimum_balance_per_octet() * octets_in_storage -
                 deposit_offset
    end
  end

  describe "encode/1" do
    test "encode service account smoke test" do
      sa = build(:service_account)
      encoded = Codec.Encoder.encode(sa)

      expected_encoded =
        sa.code_hash <>
          <<sa.balance::64-little>> <>
          <<sa.gas_limit_g::64-little>> <>
          <<sa.gas_limit_m::64-little>> <>
          <<ServiceAccount.octets_in_storage(sa)::64-little>> <>
          <<sa.deposit_offset::64-little>> <>
          <<ServiceAccount.items_in_storage(sa)::32-little>> <>
          <<sa.creation_slot::32-little>> <>
          <<sa.last_accumulation_slot::32-little>> <>
          <<sa.parent_service::32-little>>

      assert Base.encode16(encoded) == Base.encode16(expected_encoded)
    end
  end

  describe "to_json/1" do
    test "encodes service account to json format" do
      account = build(:service_account)
      expected = JsonEncoder.encode(account) |> ServiceAccount.from_json()
      assert expected == account
    end
  end
end
