defmodule HashedKeysMapTest do
  alias System.State.ServiceAccount
  use ExUnit.Case

  describe "new/1 get/2" do
    test "get on a new map" do
      map = HashedKeysMap.new(%{<<1>> => <<2>>, <<3, 4>> => <<5, 6, 7>>})
      assert map.items_in_storage == 2
      assert map.octets_in_storage == 34 + 2 + 34 + 5
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
  end
end
