defmodule Block.Extrinsic.AvailabilitySpecification do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Util.{Collections, Hash, MerkleTree}
  import Codec.Encoder

  @type t :: %__MODULE__{
          # h: hash of the work-package
          work_package_hash: Types.hash(),
          # l: auditable work bundle length
          length: non_neg_integer(),
          # u: erasure-root
          erasure_root: Types.hash(),
          # e: segment-root
          exports_root: Types.hash(),
          # n: segment-count
          segment_count: non_neg_integer()
        }

  # Formula (11.5) v0.7.2 - Y
  # p
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
    import Codec.Encoder
    # Formula (C.25) v0.7.2
    def encode(%Block.Extrinsic.AvailabilitySpecification{} = availability) do
      e(availability.work_package_hash) <>
        <<availability.length::m(work_bundle_length)>> <>
        e({availability.erasure_root, availability.exports_root}) <>
        t(availability.segment_count)
    end
  end

  use JsonDecoder
  use Sizes

  # Formula (14.17) v0.7.2
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

  # Formula (14.17) v0.7.2 - u
  @spec calculate_erasure_root(binary(), list(Types.export_segment())) :: Types.hash()
  def calculate_erasure_root(bundle_binary, exports) do
    # u = MB ([x ∣ x <− T[b♣,s♣]])
    MerkleTree.well_balanced_merkle_root(
      for x <- Utils.transpose([b_clubs(bundle_binary), s_clubs(exports)]),
          do: Collections.union_bin(x)
    )
  end

  def s_clubs(exports) do
    # C6# (s⌢P(s))
    coded_chunks =
      for s <- exports ++ WorkReport.paged_proofs(exports) do
        ErasureCoding.erasure_code(s)
      end

    # s♣ = MB#(T(...))
    for c <- Utils.transpose(coded_chunks), do: MerkleTree.well_balanced_merkle_root(c)
  end

  def b_clubs(bundle_binary) do
    # b♣ = H#(C ⌈ ∣b∣/WE ⌉(PWE (b)))
    Enum.map(
      ErasureCoding.erasure_code(
        Utils.pad_binary_right(bundle_binary, Constants.erasure_coded_piece_size())
      ),
      &Hash.default/1
    )
  end

  def decode(bin) do
    <<work_package_hash::b(hash), length::32-little, erasure_root::b(hash), exports_root::b(hash),
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
