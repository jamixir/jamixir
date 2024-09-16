defmodule Util.Hash do
  @moduledoc """
  Utility functions for hashing.
  """

  @doc """
  Hashes the given data using the Blake2b algorithm with the given number of bytes.
  """
  def blake2b_n(data, n), do: Blake2.hash2b(data, n)

  @doc """
  256 bits Blake2b hash function.
  """
  def blake2b_256(data), do: Blake2.hash2b(data, 32)

  @doc """
  256 bits keccak hash function.
  """
  def keccak_256(data), do: ExKeccak.hash_256(data)

  def default(data), do: blake2b_256(data)

  def zero, do: <<0::256>>
  def random, do: :crypto.strong_rand_bytes(32)
end
