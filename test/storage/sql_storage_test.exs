defmodule Jamixir.SqlStorageTest do
  alias Block.Extrinsic.Disputes.Judgement
  alias Util.Hash
  alias Jamixir.SqlStorage
  alias Block.Extrinsic.Assurance
  use ExUnit.Case, async: true

  import Jamixir.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Jamixir.Repo)
  end

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
