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

  # Formula (11.5) v0.6.0
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
    # Formula (C.22) v0.6.0
    def encode(%Block.Extrinsic.AvailabilitySpecification{} = availability) do
      e(availability.work_package_hash) <>
        <<availability.length::m(max_age_timeslot_lookup_anchor)>> <>
        e({availability.erasure_root, availability.exports_root}) <>
        <<availability.segment_count::16-little>>
    end
  end

  use JsonDecoder
  use Sizes
  use Codec.Decoder

  # Formula (14.16) v0.6.2
  @spec from_execution(Types.hash(), binary(), list(Types.export_segment())) ::
          __MODULE__.t()
  def from_execution(work_package_hash, bundle_binary, export_segments) do
    %__MODULE__{
      work_package_hash: work_package_hash,
      length: byte_size(bundle_binary),
      erasure_root: calculate_erasure_root(bundle_binary, export_segments),
      exports_root: MerkleTree.merkle_root(export_segments),
      segment_count: length(export_segments)
    }
  end

  # Formula (14.16) v0.6.2 - u
  @spec calculate_erasure_root(binary(), list(Types.export_segment())) :: Types.hash()
  def calculate_erasure_root(bundle_binary, exported_segments) do
    # C6# (s⌢P(s))
    coded_chunks =
      for s <- exported_segments ++ WorkReport.paged_proofs(exported_segments) do
        erasure_code_chunk(s, 6)
      end

    # s♣ = MB#(T(...))
    s_clubs =
      for c <- Utils.transpose(coded_chunks), do: MerkleTree.well_balanced_merkle_root(c)

    chunk_size = ceil(byte_size(bundle_binary) / Constants.erasure_coded_piece_size())

    # b♣ = H#(C ⌈ ∣b∣/WE ⌉(PWE (b)))
    b_clubs =
      for x <-
            erasure_code_chunk(
              Utils.pad_binary_right(bundle_binary, Constants.erasure_coded_piece_size()),
              chunk_size
            ),
          do: Hash.default(x)

    # u = MB ([x ∣ x <− T[b♣,s♣]])
    MerkleTree.well_balanced_merkle_root(
      for x <- Utils.transpose([b_clubs, s_clubs]), do: Collections.union_bin(x)
    )
  end

  defp erasure_code_chunk(bin, _n), do: ErasureCoding.erasure_code(bin)

  def decode(bin) do
    <<work_package_hash::binary-size(@hash_size), length::32-little,
      erasure_root::binary-size(@hash_size), exports_root::binary-size(@hash_size),
      segment_count::16-little, rest::binary>> = bin

    {%__MODULE__{
       work_package_hash: work_package_hash,
       length: length,
       erasure_root: erasure_root,
       exports_root: exports_root,
       segment_count: segment_count
     }, rest}
  end

  def json_mapping, do: %{work_package_hash: :hash, segment_count: :exports_count}

  def to_json_mapping, do: json_mapping()
end
