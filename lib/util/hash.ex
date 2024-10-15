defmodule Util.Hash do
  @moduledoc """
  Utility functions for hashing.
  """

  @doc """
  Hashes the given data using the Blake2b algorithm with the given number of bytes.
  """
  def blake2b_n(data, n) do
    binary_part(blake2b_256(data), 0, n)
  end

  @doc """
  256 bits Blake2b hash function.
  """
  def blake2b_256(data), do: Blake2.hash2b(data, 32)

  @doc """
  256 bits keccak hash function.
  """
  def keccak_256(data), do: ExKeccak.hash_256(data)

  def default(data), do: blake2b_256(data)

  use Sizes
  def zero, do: Utils.zero_bitstring(@hash_size)
  def one, do: Utils.zero_bitstring(@hash_size - 1) <> <<1::8>>
  def two, do: Utils.zero_bitstring(@hash_size - 1) <> <<2::8>>
  def three, do: Utils.zero_bitstring(@hash_size - 1) <> <<3::8>>

  def random, do: :crypto.strong_rand_bytes(32)
end
