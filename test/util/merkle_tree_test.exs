defmodule Util.MerkleTreeTest do
  use ExUnit.Case
  alias Util.{Hash, MerkleTree}

  describe "node/2" do
    # Helper function to simulate the hash function
    defp mock_hash(input), do: "hash(#{input})"

    test "returns zero hash for empty list" do
      assert MerkleTree.node([], &mock_hash/1) == Hash.zero()
    end

    test "returns single blob for list with one element" do
      assert MerkleTree.node(["single"], &mock_hash/1) == "single"
    end

    test "correctly hashes two elements" do
      result = MerkleTree.node(["a", "b"], &mock_hash/1)
      expected = "hash(nodeab)"
      assert result == expected
    end

    test "correctly hashes four elements" do
      result = MerkleTree.node(["a", "b", "c", "d"], &mock_hash/1)
      expected = "hash(nodehash(nodeab)hash(nodecd))"
      assert result == expected
    end

    test "correctly hashes three elements" do
      result = MerkleTree.node(["a", "b", "c"], &mock_hash/1)
      expected = "hash(nodehash(nodeab)c)"
      assert result == expected
    end

    test "correctly hashes five elements" do
      result = MerkleTree.node(["a", "b", "c", "d", "e"], &mock_hash/1)
      expected = "hash(nodehash(nodehash(nodeab)c)hash(nodede))"
      assert result == expected
    end
  end

  describe "well_balanced_merkle_root/1" do
    test "returns hash of single element" do
      blob = "single_blob"
      expected_hash = Hash.default(blob)
      assert MerkleTree.well_balanced_merkle_root([blob]) == expected_hash
    end

    test "raises ArgumentError for empty list" do
      assert_raise ArgumentError, "List of blobs cannot be empty", fn ->
        MerkleTree.well_balanced_merkle_root([])
      end
    end

    test "returns correct root for two elements" do
      blobs = ["blob1", "blob2"]
      left = "blob1"
      right = "blob2"
      expected_root = Hash.default("node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "returns correct root for three elements" do
      blobs = ["blob1", "blob2", "blob3"]
      left = Hash.default("node" <> "blob1" <> "blob2")
      right = "blob3"
      expected_root = Hash.default("node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "returns correct root for four elements" do
      blobs = ["blob1", "blob2", "blob3", "blob4"]
      left = Hash.default("node" <> "blob1" <> "blob2")
      right = Hash.default("node" <> "blob3" <> "blob4")
      expected_root = Hash.default("node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "handles even number of elements" do
      blobs = ["blob1", "blob2", "blob3", "blob4", "blob5", "blob6"]
      left_left = Hash.default("node" <> "blob1" <> "blob2")
      left_right = "blob3"
      right_left = Hash.default("node" <> "blob4" <> "blob5")
      right_right = "blob6"
      left = Hash.default("node" <> left_left <> left_right)
      right = Hash.default("node" <> right_left <> right_right)
      expected_root = Hash.default("node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "handles odd number of elements" do
      blobs = ["blob1", "blob2", "blob3", "blob4", "blob5"]
      left = Hash.default("node" <> Hash.default("node" <> "blob1" <> "blob2") <> "blob3")
      right = Hash.default("node" <> "blob4" <> "blob5")
      expected_root = Hash.default("node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end
  end

  describe "c_preprocess/2" do
    test "empty list" do
      assert MerkleTree.c_preprocess([], &Hash.default/1) == [Hash.zero()]
    end

    test "one element list" do
      blobs = ["blob1"]
      expected_hashes = [Hash.default("leafblob1")]
      assert MerkleTree.c_preprocess(blobs, &Hash.default/1) == expected_hashes
    end

    test "two elements list" do
      blobs = ["blob1", "blob2"]
      expected_hashes = [Hash.default("leafblob1"), Hash.default("leafblob2")]
      assert MerkleTree.c_preprocess(blobs, &Hash.default/1) == expected_hashes
    end

    test "c_preprocess/2" do
      blobs = ["blob1", "blob2", "blob3"]

      expected_hashes = [
        Hash.default("leafblob1"),
        Hash.default("leafblob2"),
        Hash.default("leafblob3"),
        Hash.zero()
      ]

      assert MerkleTree.c_preprocess(blobs, &Hash.default/1) == expected_hashes
    end
  end

  describe "merkle_root/1" do
    test "test that merkle root pre-proccesses the list" do
      blobs = ["blob1", "blob2", "blob3", "blob4", "blob5", "blob6"]
      processed_items = MerkleTree.c_preprocess(blobs, &Hash.default/1)
      expected_root = MerkleTree.well_balanced_merkle_root(processed_items, &Hash.default/1)
      assert MerkleTree.merkle_root(blobs) == expected_root
    end
  end

  defp identity_hash(x), do: x

  describe "justification/4" do
    test "returns correct justification with x parameter" do
      list = ["a", "b", "c", "d", "e", "f", "g", "h"]
      index = 3
      x = 1
      result = MerkleTree.justification(list, index, &identity_hash/1, x)

      assert result == ["nodenodeleafaleafbnodeleafcleafd", "nodeleafeleaff"]
    end

    test "returns empty list when x is greater than or equal to log2(length)" do
      list = ["a", "b", "c", "d"]
      index = 2
      x = 2
      assert MerkleTree.justification(list, index, &identity_hash/1, x) == []
    end

    test "raises ArgumentError for empty list" do
      assert MerkleTree.justification([], 0, &identity_hash/1, 1) == []
    end

    test "returns correct justification for odd number of elements" do
      list = ["a", "b", "c", "d", "e"]
      index = 3
      result = MerkleTree.justification(list, index, &identity_hash/1, 2)

      assert result == ["nodenodeleafaleafbnodeleafcleafd"]
    end
  end

  describe "trace/3" do
    test "trace for power of two list" do
      list = ["a", "b", "c", "d", "e", "f", "g", "h"]
      result = MerkleTree.trace(list, 3, &mock_hash/1)
      assert result == ["hash(nodehash(nodeef)hash(nodegh))", "hash(nodeab)", "c"]
    end

    test "trace for non power of two list" do
      list = ["a", "b", "c", "d", "e", "f", "g"]
      result = MerkleTree.trace(list, 3, &mock_hash/1)
      assert result == ["hash(nodehash(nodede)hash(nodefg))", "hash(nodeab)", "c"]
    end
  end

  describe "justification_l/4" do
    test "returns correct leaf hashes for given range" do
      list = ["a", "b", "c", "d", "e", "f", "g", "h"]
      index = 1
      x = 1
      result = MerkleTree.justification_l(list, index, &identity_hash/1, x)

      # For i=1, x=1:
      # start_idx = 2^(x*i) = 2^1 = 2
      # end_idx = min(2^1 + 2^1, 8) = min(4, 8) = 4
      # Should return hashes of elements [2,3]
      assert result == ["leafc", "leafd"]
    end

    test "handles edge of list" do
      list = ["a", "b", "c", "d"]
      index = 1
      x = 1
      result = MerkleTree.justification_l(list, index, &identity_hash/1, x)

      # Should return hashes of elements [2,3]
      assert result == ["leafc", "leafd"]
    end

    test "returns empty list when start index exceeds list length" do
      list = ["a", "b", "c"]
      index = 2
      x = 1
      result = MerkleTree.justification_l(list, index, &identity_hash/1, x)

      # start_idx = 2^(x*i) = 2^2 = 4
      # This exceeds list length, so should return empty list
      assert result == []
    end

    test "handles larger x values" do
      list = ["a", "b", "c", "d", "e", "f", "g", "h"]
      index = 1
      x = 2
      result = MerkleTree.justification_l(list, index, &identity_hash/1, x)

      # start_idx = 2^(x*i) = 2^2 = 4
      # end_idx = min(4 + 4, 8) = 8
      # Should return hashes of elements [4,5,6,7]
      assert result == ["leafe", "leaff", "leafg", "leafh"]
    end

    test "handles x=0 case" do
      list = ["a", "b", "c", "d"]
      index = 1
      x = 0
      result = MerkleTree.justification_l(list, index, &identity_hash/1, x)

      # start_idx = 2^0 = 1
      # end_idx = min(1 + 1, 4) = 2
      # Should return hash of element [1]
      assert result == ["leafb"]
    end

    test "i=0 case" do
      list = ["a"]
      result = MerkleTree.justification_l(list, 0, &identity_hash/1, 6)
      assert result == []
    end
  end
end
