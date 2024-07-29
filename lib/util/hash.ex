defmodule Util.Hash do
  @moduledoc """
  Utility functions for hashing.
  """

  @doc """
  256 bits Blake2b hash function.
  """
  def blake2b_256(data) do
    # Generate Blake2b hash with default output size (64 bytes)
    full_hash = :crypto.hash(:blake2b, data)
    # Truncate to 256 bits (32 bytes)
    <<output::binary-size(32), _rest::binary>> = full_hash
    output
  end
end
