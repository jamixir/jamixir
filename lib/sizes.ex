defmodule Sizes do
  def hash, do: 32
  def bitfield, do: div(Constants.core_count() + 7, 8)

  def merkle_root, do: 64
  def merkle_root_bits, do: 512

  defmacro __using__(_) do
    quote do
      @bandersnatch_proof_size 784
      @bitfield_size Sizes.bitfield()
      @hash_size Sizes.hash()
      @signature_size 64
      @validator_size 2
    end
  end
end
