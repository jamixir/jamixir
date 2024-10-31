defmodule Sizes do
  def hash, do: 32
  def bitfield, do: div(Constants.core_count() + 7, 8)

  def merkle_root, do: 64
  def merkle_root_bits, do: 512
  def signature, do: 64

  def bandersnatch_signature, do: 96
  def bandersnatch_proof, do: 784

  defmacro __using__(_) do
    quote do
      @bandersnatch_proof_size Sizes.bandersnatch_proof()
      @bitfield_size Sizes.bitfield()
      @hash_size Sizes.hash()
      @signature_size Sizes.signature()
      @validator_index_size 2
    end
  end
end
