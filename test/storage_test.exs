defmodule StorageTest do
  alias Block.Header
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory

  describe "binary storage" do
    test "store/2 stores the value in the storage" do
      :ok = Storage.put(<<1, 2, 3, 4>>)
      assert Storage.get(Hash.default(<<1, 2, 3, 4>>)) == <<1, 2, 3, 4>>
    end

    test "store/2 overwrites the existing value in the storage" do
      :ok = Storage.put(<<1, 2, 3, 4>>)
      :ok = Storage.put(<<1, 2, 3, 4>>)
      assert Storage.get(Hash.default(<<1, 2, 3, 4>>)) == <<1, 2, 3, 4>>
    end

    test "get/2 returns nil if the key does not exist in the storage" do
      assert Storage.get(Hash.random()) == nil
    end

    test "delete/2 removes the key and its associated value from the storage" do
      hash = Hash.default(<<1, 2, 3, 4>>)
      Storage.put(<<1, 2, 3, 4>>)
      Storage.delete(hash)
      assert Storage.get(hash) == nil
    end
  end

  import TestHelper

  describe "objects storage" do
    setup_validators(1)

    test "store header" do
      header = build(:decodable_header)
      :ok = Storage.put(header)
      hash = Hash.default(Encodable.encode(header))
      assert Storage.get(hash, Header) == header
    end
  end
end
