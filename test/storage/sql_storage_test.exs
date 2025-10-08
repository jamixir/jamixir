defmodule Jamixir.SqlStorageTest do
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
end
