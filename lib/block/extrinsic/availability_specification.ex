defmodule Block.Extrinsic.AvailabilitySpecification do
  alias Util.Collections
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Util.{Hash, MerkleTree}

  @type t :: %__MODULE__{
          # h: hash of the work-package
          work_package_hash: Types.hash(),
          # l: auditable work bundle length
          length: Types.max_age_timeslot_lookup_anchor(),
          # u: erasure-root
          erasure_root: Types.hash(),
          # e: segment-root
          exports_root: Types.hash(),
          # n: segment-count
          segment_count: non_neg_integer()
        }

  # Formula (11.5) v0.5
  # h
  defstruct work_package_hash: Hash.zero(),
            # l
            length: 0,
            # u
            erasure_root: Hash.zero(),
            # e
            exports_root: Hash.zero(),
            # n
            segment_count: 0

  defimpl Encodable do
    use Codec.Encoder
    # Formula (C.22) v0.5
    def encode(%Block.Extrinsic.AvailabilitySpecification{} = availability) do
      e(availability.work_package_hash) <>
        e_le(availability.length, 4) <>
        e({availability.erasure_root, availability.exports_root}) <>
        e_le(availability.segment_count, 2)
    end
  end

  use JsonDecoder
  use Sizes
  use Codec.Decoder

  # Formula (207) v0.4.5
  @spec from_package_execution(Types.hash(), binary(), list(Types.export_segment())) ::
          Block.Extrinsic.t()
  def from_package_execution(work_package_hash, bundle_binary, export_segments) do
    %__MODULE__{
      work_package_hash: work_package_hash,
      length: length(export_segments),
      erasure_root: calculate_erasure_root(bundle_binary, export_segments),
      exports_root: MerkleTree.merkle_root(export_segments)
    }
  end

  # Formula (207) v0.4.5 - u
  @spec calculate_erasure_root(binary(), list(Types.export_segment())) :: Types.hash()
  defp calculate_erasure_root(bundle_binary, exported_segments) do
    coded_chunks =
      for s <- exported_segments ++ WorkReport.paged_proofs(exported_segments) do
        erasure_code_chunk(s, 6)
      end

    s_clubs =
      for c <- Utils.transpose(coded_chunks), do: MerkleTree.well_balanced_merkle_root(c)

    chunk_size = ceil(byte_size(bundle_binary) / Constants.erasure_coded_piece_size())

    b_clubs =
      for x <-
            erasure_code_chunk(
              Utils.pad_binary_right(bundle_binary, Constants.erasure_coded_piece_size()),
              chunk_size
            ),
          do: Hash.default(x)

    MerkleTree.well_balanced_merkle_root(
      Collections.union(for x <- Utils.transpose([b_clubs, s_clubs]), do: x)
    )
  end

  # TODO
  defp erasure_code_chunk(_binary, _n), do: []

  def decode(bin) do
    <<work_package_hash::binary-size(@hash_size), length::binary-size(4),
      erasure_root::binary-size(@hash_size), exports_root::binary-size(@hash_size),
      segment_count::binary-size(2), rest::binary>> = bin

    {%__MODULE__{
       work_package_hash: work_package_hash,
       length: de_le(length, 4),
       erasure_root: erasure_root,
       exports_root: exports_root,
       segment_count: de_le(segment_count, 2)
     }, rest}
  end

  def json_mapping, do: %{work_package_hash: :hash, segment_count: :exports_count}
end
