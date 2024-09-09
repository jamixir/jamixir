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

  describe "c_preprocess/2" do
    test "empty list" do
      assert MerkleTree.c_preprocess([], &Hash.blake2b_256/1) == []
    end

    test "one element list" do
      blobs = ["blob1"]
      expected_hashes = [Hash.blake2b_256("$leafblob1")]
      assert MerkleTree.c_preprocess(blobs, &Hash.blake2b_256/1) == expected_hashes
    end

    test "two elements list" do
      blobs = ["blob1", "blob2"]
      expected_hashes = [Hash.blake2b_256("$leafblob1"), Hash.blake2b_256("$leafblob2")]
      assert MerkleTree.c_preprocess(blobs, &Hash.blake2b_256/1) == expected_hashes
    end

    test "c_preprocess/2" do
      blobs = ["blob1", "blob2", "blob3"]

      expected_hashes = [
        Hash.blake2b_256("$leafblob1"),
        Hash.blake2b_256("$leafblob2"),
        Hash.blake2b_256("$leafblob3"),
        Hash.zero()
      ]

      assert MerkleTree.c_preprocess(blobs, &Hash.blake2b_256/1) == expected_hashes
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
end
