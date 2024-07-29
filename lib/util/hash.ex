defmodule Util.Hash do
  @moduledoc """
  Utility functions for hashing.
  """

  @doc """
  256 bits Blake2b hash function.
  """
  def blake2b_256(data) do
    Blake2.hash2b(data, 32)
  end
end
