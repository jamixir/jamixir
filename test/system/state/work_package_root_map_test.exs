defmodule System.State.WorkPackageRootMapTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.WorkPackageRootMap
  alias Util.Hash

  describe "create/1" do
    test "creates a map of work package hashes to segment roots" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one(), exports_root: Hash.two()}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: Hash.three(), exports_root: Hash.four()}
        )

      assert %{<<1::256>> => <<2::256>>, <<3::256>> => <<4::256>>} =
               WorkPackageRootMap.create([w1, w2])
    end

    test "handles empty list of work reports" do
      assert %{} = WorkPackageRootMap.create([])
    end

    test "overwrites duplicate work package hashes with the last occurrence" do
      w1 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one(), exports_root: Hash.two()}
        )

      w2 =
        build(:work_report,
          specification: %{work_package_hash: Hash.one(), exports_root: Hash.three()}
        )

      assert %{<<1::256>> => <<3::256>>} = WorkPackageRootMap.create([w1, w2])
    end
  end

  describe "initial_state/0" do
    test "returns a list of empty maps with length equal to epoch_length" do
      initial_state = WorkPackageRootMap.initial_state()
      assert length(initial_state) == Constants.epoch_length()
      assert Enum.all?(initial_state, &(map_size(&1) == 0))
    end
  end
end
