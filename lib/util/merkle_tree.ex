defmodule Util.MerkleTree do
  @moduledoc """
  A module for constructing Well-Balanced Binary Merkle Trees.
  """

  alias Util.Hash

  @doc """
  Constructs a well-balanced binary Merkle tree and returns the root hash.
  """
  def well_balanced_merkle_root(list_of_blobs, hash_func \\ &Hash.blake2b_256/1) do
    case list_of_blobs do
      [] -> raise ArgumentError, "List of blobs cannot be empty"
      # equation (299)
      [single_blob] -> hash_func.(single_blob)
      _ -> node(list_of_blobs, hash_func)
    end
  end

  @doc """
  Node function N for the Merkle tree.
  equation (297)
  """
  defp node([], _hash_func), do: <<0::256>>

  defp node([single_blob], _hash_func), do: single_blob

  defp node(list_of_blobs, hash_func) do
    mid = div(length(list_of_blobs), 2)
    {left, right} = Enum.split(list_of_blobs, mid)
    left_hash = node(left, hash_func)
    right_hash = node(right, hash_func)
    hash_func.("$node" <> left_hash <> right_hash)
  end
end
