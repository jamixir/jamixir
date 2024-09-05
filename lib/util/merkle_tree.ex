defmodule Util.MerkleTree do
  @moduledoc """
  A module for constructing Well-Balanced Binary Merkle Trees.
  """

  alias Util.Hash

  @doc """
    Constructs a well-balanced binary Merkle tree and returns the root hash.
    Formula (299) v0.3.4
  """
  @spec well_balanced_merkle_root(list(binary())) :: Hash.t()
  def well_balanced_merkle_root(l), do: well_balanced_merkle_root(l, &Hash.default/1)
  @spec well_balanced_merkle_root(list(binary()), (binary() -> Hash.t())) :: Hash.t()
  def well_balanced_merkle_root([], _), do: raise(ArgumentError, "List of blobs cannot be empty")
  def well_balanced_merkle_root([single_blob], hash_func), do: hash_func.(single_blob)
  def well_balanced_merkle_root(list_of_blobs, hash_func), do: node(list_of_blobs, hash_func)

  # Formula (300) v0.3.4
  @spec merkle_root(list(binary())) :: Hash.t()
  def merkle_root(v), do: merkle_root(v, &Hash.default/1)
  @spec merkle_root(list(binary()), (binary() -> Hash.t())) :: Hash.t()
  def merkle_root(list, hash_func), do: node(c_preprocess(list, hash_func), hash_func)

  # Formula (303) v0.3.4
  @spec c_preprocess(list(binary()), (binary() -> Hash.t())) :: list(Hash.t())
  def c_preprocess([], _), do: []

  def c_preprocess(list, hash_func) do
    list
    |> Enum.map(&hash_func.("$leaf" <> &1))
    |> pad_to_power_of_two(Hash.zero())
  end

  defp pad_to_power_of_two(list, pad_value) do
    next_power_of_two = next_power_of_two(length(list))
    padding = next_power_of_two - length(list)
    list ++ List.duplicate(pad_value, padding)
  end

  defp next_power_of_two(n) do
    :math.pow(2, Float.ceil(:math.log2(n))) |> round()
  end

  # Node function N for the Merkle tree.
  # Formula (297) v0.3.4
  @spec node(list(binary()), (binary() -> Hash.t())) :: binary() | Hash.t()
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
