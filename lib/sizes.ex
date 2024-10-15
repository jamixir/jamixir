defmodule Sizes do
  def hash, do: 32
  def signature, do: 64
  def assurance_values, do: div(Constants.core_count() + 7, 8)

  def merkle_root, do: 64
  def merkle_root_bits, do: 512
end
