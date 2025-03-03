defmodule Util.Hash do
  use Sizes

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

  # Generate hash functions for numbers 0 to 5
  # use as Hash.zero(), Hash.one()  etc.
  for {name, i} <- Enum.zip([:zero, :one, :two, :three, :four, :five], 0..5) do
    def unquote(name)() do
      Utils.zero_bitstring(@hash_size - 1) <> <<unquote(i)::8>>
    end
  end

  def random, do: :crypto.strong_rand_bytes(32)
  def random(size), do: :crypto.strong_rand_bytes(size)
end
