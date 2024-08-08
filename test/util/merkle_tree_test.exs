defmodule Util.MerkleTreeTest do
  use ExUnit.Case
  alias Util.{MerkleTree, Hash}

  describe "well_balanced_merkle_root/1" do
    test "returns hash of single element" do
      blob = "single_blob"
      expected_hash = Hash.blake2b_256(blob)
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
      expected_root = Hash.blake2b_256("$node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "returns correct root for three elements" do
      blobs = ["blob1", "blob2", "blob3"]
      left = "blob1"
      right = Hash.blake2b_256("$node" <> "blob2" <> "blob3")
      expected_root = Hash.blake2b_256("$node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "returns correct root for four elements" do
      blobs = ["blob1", "blob2", "blob3", "blob4"]
      left = Hash.blake2b_256("$node" <> "blob1" <> "blob2")
      right = Hash.blake2b_256("$node" <> "blob3" <> "blob4")
      expected_root = Hash.blake2b_256("$node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "handles even number of elements" do
      blobs = ["blob1", "blob2", "blob3", "blob4", "blob5", "blob6"]
      left_left = "blob1"
      left_right = Hash.blake2b_256("$node" <> "blob2" <> "blob3")
      right_left = "blob4"
      right_right = Hash.blake2b_256("$node" <> "blob5" <> "blob6")
      left = Hash.blake2b_256("$node" <> left_left <> left_right)
      right = Hash.blake2b_256("$node" <> right_left <> right_right)
      expected_root = Hash.blake2b_256("$node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end

    test "handles odd number of elements" do
      blobs = ["blob1", "blob2", "blob3", "blob4", "blob5"]
      left = Hash.blake2b_256("$node" <> "blob1" <> "blob2")

      right =
        Hash.blake2b_256("$node" <> "blob3" <> Hash.blake2b_256("$node" <> "blob4" <> "blob5"))

      expected_root = Hash.blake2b_256("$node" <> left <> right)
      assert MerkleTree.well_balanced_merkle_root(blobs) == expected_root
    end
  end
end
