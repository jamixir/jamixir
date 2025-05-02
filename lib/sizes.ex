defmodule Sizes do
  def hash, do: 32
  def bitfield, do: div(Constants.core_count() + 7, 8)

  def merkle_root, do: 64
  def merkle_root_bits, do: __MODULE__.merkle_root() * 8
  def signature, do: 64

  def bandersnatch_signature, do: 96
  def bandersnatch_proof, do: 784
  def export_segment, do: Constants.erasure_coded_piece_size() * 6
  def erasure_coded_piece, do: Constants.erasure_coded_piece_size()

  defmacro __using__(_) do
    quote do
      @bandersnatch_proof_size Sizes.bandersnatch_proof()
      @bitfield_size Sizes.bitfield()
      @hash_size Sizes.hash()
      @signature_size Sizes.signature()
      @validator_index_size 2
      @export_segment_size Sizes.export_segment()
      @max_work_items Constants.max_work_items()
      @service_index_size 4
      @timeslot_size 4
      @segment_shard_size div(Sizes.export_segment(), Constants.core_count())
    end
  end
end
