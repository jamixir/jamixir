defmodule Merklization do
  @moduledoc """
  Implementation of Merklization based on a Patricia Merkle Trie.
  D.2. Merklization
  D.2.1. Node encoding and Trie identification
  """

  alias Util.Hash

  @doc """
  Main function for Merklization.
  Converts a serialized mapping into its Merkle root.
  """
  def merkelize(serialized_mapping) do
    trie = build_trie(serialized_mapping)
    get_merkle_root(trie)
  end

  # Build a binary Patricia Merkle Trie from a serialized mapping.
  def build_trie(serialized_mapping) do
    Enum.reduce(serialized_mapping, %{}, fn {k, v}, acc ->
      put_in_trie(acc, k, v)
    end)
  end

  # Inserts a key-value pair into the Trie.
  # Determines whether to insert as a branch or leaf node.
  def put_in_trie(trie, key, value) do
    Map.put(trie, key, value)
  end

  # Computes the Merkle root from the Patricia Trie.
  def get_merkle_root(trie) do
    case Map.to_list(trie) do
      [] ->
        Hash.default("")

      [{_key, %{} = nested_trie}] ->
        get_merkle_root(nested_trie)

      [{key, value}] ->
        encode_leaf(key, value, true)

      list when length(list) > 1 ->
        [left, right | _] = list
        left_hash = get_merkle_root(Map.new([left]))
        right_hash = get_merkle_root(Map.new([right]))
        encode_branch(left_hash, right_hash)
    end
  end


  # Encodes a branch node into 512 bits.
  # Takes two hash values (left and right) and returns a 512-bit binary.
  def encode_branch(left_hash, right_hash) do
    <<0::1, left_hash::256, right_hash::256>>
  end

 # Encodes a leaf node into 512 bits.
  # Takes a key and value, and a flag indicating if the value is embedded.
  def encode_leaf(key, value, embedded_value?) do
    key_binary = binary_part(key, 0, min(byte_size(key), 31))
    padding_size = 31 - byte_size(key_binary)
    padded_key = <<key_binary::binary, 0::size(padding_size * 8)>>

    if embedded_value? do
      size = byte_size(value)
      <<1::1, 0::1, size::6, padded_key::binary-size(248), value::binary-size(256)>>
    else
      hashed_value = Hash.blake2b_256(value)
      <<1::1, 1::1, 0::6, padded_key::binary-size(248), hashed_value::binary-size(256)>>
    end
  end


end


defmodule MerklizationTest do
  use ExUnit.Case
  alias Merklization
  alias Util.Hash

  test "merkelize/1 computes correct Merkle root" do
    input = %{"a" => "value1", "b" => "value2"}
    assert Merklization.merkelize(input) != ""
  end

  test "build_trie/1 builds a correct Trie" do
    input = %{"a" => "value1", "b" => "value2"}
    trie = Merklization.build_trie(input)
    assert Map.keys(trie) == ["a", "b"]
  end

  test "put_in_trie/3 inserts a key-value pair" do
    trie = %{}
    updated_trie = Merklization.put_in_trie(trie, "a", "value1")
    assert Map.get(updated_trie, "a") == "value1"
  end

  test "get_merkle_root/1 computes root of empty Trie" do
    assert Merklization.get_merkle_root(%{}) == Hash.default("")
  end

  test "encode_branch/2 encodes correctly" do
    left_hash = Hash.default("left")
    right_hash = Hash.default("right")
    assert byte_size(Merklization.encode_branch(left_hash, right_hash)) == 32
  end

  test "encode_leaf/3 encodes embedded value correctly" do
    key = "key"
    value = "value"
    encoded = Merklization.encode_leaf(key, value, true)
    assert byte_size(encoded) == 64
  end

  test "encode_leaf/3 encodes hashed value correctly" do
    key = "key"
    value = "value"
    encoded = Merklization.encode_leaf(key, value, false)
    assert byte_size(encoded) == 64
  end
end
