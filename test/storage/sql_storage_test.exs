defmodule Jamixir.SqlStorageTest do
  alias Jamixir.DBCase
  alias Block.Extrinsic.Disputes.Judgement
  alias Util.Hash
  alias Jamixir.SqlStorage
  alias Block.Extrinsic.Assurance
  use ExUnit.Case, async: true
  use DBCase
  import Jamixir.Factory

  describe "assurance operations" do
    test "save and retrieve assurance" do
      assurance1 = build(:assurance, validator_index: 0)
      assurance2 = build(:assurance, validator_index: 1)
      assert {:ok, _record} = SqlStorage.save(assurance1)
      assert {:ok, _record} = SqlStorage.save(assurance2)
      [record1, record2] = SqlStorage.get_all(Assurance)
      assert record1 == assurance1
      assert record2 == assurance2
    end

    test "save updates existing assurance" do
      assurance = build(:assurance, validator_index: 0)
      assert {:ok, _record} = SqlStorage.save(assurance)
      updated_assurance = %Assurance{assurance | bitfield: <<1::344>>}
      assert {:ok, _record} = SqlStorage.save(updated_assurance)
      [record] = SqlStorage.get_all(Assurance)
      assert record == updated_assurance
    end

    test "get assurance for specific hash and validator" do
      assurance = build(:assurance, validator_index: 2)
      assert {:ok, _record} = SqlStorage.save(assurance)
      record = SqlStorage.get(Assurance, [assurance.hash, 2])
      assert record == assurance
    end

    test "get all assurance for specific hash" do
      SqlStorage.save(build(:assurance, validator_index: 2, hash: <<1::256>>))
      SqlStorage.save(build(:assurance, validator_index: 3, hash: <<1::256>>))
      SqlStorage.save(build(:assurance, validator_index: 4, hash: <<1::256>>))

      records = SqlStorage.get_all(Assurance, <<1::256>>)
      assert length(records) == 3

      SqlStorage.clean(Assurance)
      records = SqlStorage.get_all(Assurance, <<1::256>>)
      assert Enum.empty?(records)
    end

    test "get assurance returns nil when not found" do
      record = SqlStorage.get(Assurance, [Hash.random(), 99])
      assert record == nil
    end
  end

  describe "judgement operations" do
    test "save and retrieve judgements by epoch" do
      judgement1 = build(:judgement, validator_index: 0)
      judgement2 = build(:judgement, validator_index: 1)
      epoch = 42
      hash = Hash.random()
      assert {:ok, _record} = SqlStorage.save(judgement1, hash, epoch)
      assert {:ok, _record} = SqlStorage.save(judgement2, hash, epoch)
      [record1, record2] = SqlStorage.get_all(Judgement, epoch)
      assert record1 == judgement1
      assert record2 == judgement2
    end
  end
end
