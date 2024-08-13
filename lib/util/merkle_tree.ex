defmodule Util.MerkleTree do
  @moduledoc """
  A module for constructing Well-Balanced Binary Merkle Trees.
  """

  alias Util.Hash

  @doc """
    Constructs a well-balanced binary Merkle tree and returns the root hash.
  """
  def well_balanced_merkle_root(l), do: well_balanced_merkle_root(l, &Hash.blake2b_256/1)
  def well_balanced_merkle_root([], _), do: raise(ArgumentError, "List of blobs cannot be empty")
  def well_balanced_merkle_root([single_blob], hash_func), do: hash_func.(single_blob)
  def well_balanced_merkle_root(list_of_blobs, hash_func), do: node(list_of_blobs, hash_func)

  # Node function N for the Merkle tree.
  # equation (297)

  defp node([], _), do: <<0::256>>
  defp node([single_blob], _), do: single_blob

  defp node(list_of_blobs, hash_func) do
    mid = div(length(list_of_blobs), 2)
    {left, right} = Enum.split(list_of_blobs, mid)
    left_hash = node(left, hash_func)
    right_hash = node(right, hash_func)
    hash_func.("$node" <> left_hash <> right_hash)
  end
end
