defmodule HashedKeysMapTest do
  alias System.State.ServiceAccount
  import Codec.Encoder
  use ExUnit.Case

  describe "new/1 get/2" do
    test "new map with storage items" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, <<3, 4>> => <<5, 6, 7>>})
      assert map.items_in_storage == 2
      assert map.octets_in_storage == 34 + 2 + 34 + 5
    end

    test "new map with preimage_l items" do
      map = HashedKeysMap.new(%{{h(<<1>>), 8} => []})
      assert map.items_in_storage == 2
      assert map.octets_in_storage == 81 + 8
    end

    test "map with both kinds of keys" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, {h(<<3, 4>>), 5} => [1, 2]})
      assert map.items_in_storage == 3
      assert map.octets_in_storage == 34 + 2 + 81 + 5
    end
  end

  describe "drop/2" do
    test "drop keys" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, <<7>> => <<8>>})
      dropped = HashedKeysMap.drop(map, [<<1>>])
      assert length(Map.keys(dropped.original_map)) == 1
      assert length(Map.keys(dropped.hashed_map)) == 1
      assert dropped.items_in_storage == 1
      assert dropped.octets_in_storage == 36
      assert HashedKeysMap.get(dropped, <<1>>) == nil
    end

    test "drop unexistent keys" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, <<7>> => <<8>>})
      dropped = HashedKeysMap.drop(map, [<<2>>])
      assert map == dropped
    end

    test "drop preimage_storage_l key" do
      map = HashedKeysMap.new(%{{h(<<1>>), 8} => []})
      dropped = HashedKeysMap.drop(map, [{h(<<1>>), 8}])
      assert map_size(dropped.hashed_map) == 0
      assert dropped.items_in_storage == 0
      assert dropped.octets_in_storage == 0
      assert HashedKeysMap.get(dropped, {h(<<1>>), 8}) == nil
    end
  end

  describe "has_key?" do
    test "has_key uses only hash keys" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, <<7>> => <<8>>})
      assert HashedKeysMap.has_key?(map, <<1>>)
      assert HashedKeysMap.has_key?(map, <<7>>)
      refute HashedKeysMap.has_key?(map, <<9>>)
    end

    test "works without original_map" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, <<7>> => <<8>>})
      map = %{map | original_map: %{}}
      assert HashedKeysMap.has_key?(map, <<1>>)
      assert map[<<1>>] == <<2>>
      {<<2>>, new_map} = pop_in(map, [<<1>>])
      assert map_size(new_map.hashed_map) == 1
    end
  end

  describe "Access Behaviour" do
    setup do
      {:ok, map: HashedKeysMap.new(%{<<1>> => <<2>>, <<7>> => <<8>>})}
    end

    test "get_in", %{map: map} do
      service = %ServiceAccount{storage: map}
      assert get_in(service, [:storage, <<1>>]) == <<2>>
      assert get_in(service, [:storage, <<2>>]) == nil
    end

    test "put_in not exists before", %{map: map} do
      service = %ServiceAccount{storage: map}
      old_count = service.storage.items_in_storage
      old_octets = service.storage.octets_in_storage
      new_s = put_in(service, [:storage, <<1, 3>>], <<4, 4>>)
      assert get_in(new_s, [:storage, <<1, 3>>]) == <<4, 4>>
      assert new_s.storage.items_in_storage == old_count + 1
      assert new_s.storage.octets_in_storage == old_octets + 34 + 4
    end

    test "put_in exists before", %{map: map} do
      service = %ServiceAccount{storage: map}
      old_count = service.storage.items_in_storage
      old_octets = service.storage.octets_in_storage
      new_s = put_in(service, [:storage, <<1>>], <<4, 4>>)
      assert get_in(new_s, [:storage, <<1>>]) == <<4, 4>>
      assert new_s.storage.items_in_storage == old_count
      assert new_s.storage.octets_in_storage == old_octets + 1
    end

    test "put_in preimage_storage_l key", %{map: map} do
      service = %ServiceAccount{storage: map}
      old_count = service.storage.items_in_storage
      old_octets = service.storage.octets_in_storage
      new_s = put_in(service, [:storage, {h(<<4, 4>>), 7}], [])
      assert get_in(new_s, [:storage, {h(<<4, 4>>), 7}]) == []
      assert new_s.storage.items_in_storage == old_count + 2
      assert new_s.storage.octets_in_storage == old_octets + 81 + 7
    end

    test "pop_in", %{map: map} do
      service = %ServiceAccount{storage: map}
      old_count = service.storage.items_in_storage
      old_octets = service.storage.octets_in_storage
      {_, new_s} = pop_in(service, [:storage, <<1>>])
      assert get_in(new_s, [:storage, <<1>>]) == nil
      assert new_s.storage.items_in_storage == old_count - 1
      # 1 byte less for key and 1 byte less for value
      assert new_s.storage.octets_in_storage == old_octets - 2 - 34
    end

    test "pop_in with preimage_storage_l item", %{map: map} do
      k = {h(<<4, 4>>), 77}
      service = %ServiceAccount{storage: map}
      new_s = put_in(service, [:storage, k], [3, 2])

      old_count = new_s.storage.items_in_storage
      old_octets = new_s.storage.octets_in_storage
      {_, new_s} = pop_in(service, [:storage, k])
      assert get_in(new_s, [:storage, k]) == nil
      assert new_s.storage.items_in_storage == old_count - 2
      # 1 byte less for key and 1 byte less for value
      assert new_s.storage.octets_in_storage == old_octets - 81 - 77
    end
  end
end
