defmodule Sizes do
  def hash, do: 32
  def signature, do: 64
  def bitfield, do: div(Constants.core_count() + 7, 8)

  def merkle_root, do: 64
  def merkle_root_bits, do: 512

  defmacro __using__(_) do
    quote do
      @signature_size 64
      @validator_size 2
      @hash_size 32
      @bitfield_size div(Constants.core_count() + 7, 8)
    end
  end
end
