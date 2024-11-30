defmodule Block.Extrinsic.WorkItem do
  @moduledoc """
  Work Item
  Section 14.3
  """
  alias Block.Extrinsic.{Guarantee.WorkResult, WorkPackage}
  alias Util.{Hash, MerkleTree}
  use Codec.Encoder
  use Codec.Decoder
  use Sizes

  @type t :: %__MODULE__{
          # s
          service: non_neg_integer(),
          # c
          code_hash: Types.hash(),
          # y
          payload: binary(),
          # g
          gas_limit: non_neg_integer(),
          # e
          export_count: non_neg_integer(),
          # i
          # TODO: update the type to be H ∪ (H⊞)
          import_segments: list({Types.hash(), non_neg_integer()}),
          # x
          extrinsic: list({Types.hash(), non_neg_integer()})
        }

  # Formula (195) v0.4.5
  defstruct [
    # s: The identifier of the service to which it relates
    service: 0,
    # c: The code hash of the service at the time of reporting
    code_hash: Hash.zero(),
    # y: A payload blob
    payload: <<>>,
    # g: A gas limit
    gas_limit: 0,
    # e: The number of data segments exported by this work item
    export_count: 0,
    # i: A sequence of imported data segments identified by the root of the segments tree
    import_segments: [],
    # x: A sequence of hashed blob hashes and lengths to be introduced in this block
    extrinsic: []
  ]

  defimpl Encodable do
    alias Block.Extrinsic.WorkItem
    alias Codec.{Encoder, VariableSize}
    # Formula (C.26) v0.5.0
    def encode(%WorkItem{} = wi) do
      Encoder.encode({
        e_le(wi.service, 4),
        wi.code_hash,
        vs(wi.payload),
        e_le(wi.gas_limit, 8),
        vs(encode_import_segments(wi)),
        vs(encode_extrinsic(wi)),
        e_le(wi.export_count, 2)
      })
    end

    use Codec.Encoder

    defp encode_import_segments(work_item) do
      for {h, i} <- work_item.import_segments, do: {h, e_le(i, 2)}
    end

    defp encode_extrinsic(work_item) do
      for {h, i} <- work_item.extrinsic, do: {h, e_le(i, 4)}
    end
  end

  def decode(bin) do
    <<service::binary-size(4), bin::binary>> = bin
    <<code_hash::binary-size(@hash_size), bin::binary>> = bin
    {payload, bin} = VariableSize.decode(bin, :binary)
    <<gas_limit::binary-size(8), bin::binary>> = bin
    {import_segments, bin} = VariableSize.decode(bin, :list_of_tuples, @hash_size, 2)
    {extrinsic, bin} = VariableSize.decode(bin, :list_of_tuples, @hash_size, 4)
    <<export_count::binary-size(2), rest::binary>> = bin

    {%__MODULE__{
       service: de_le(service, 4),
       code_hash: code_hash,
       payload: payload,
       gas_limit: de_le(gas_limit, 8),
       import_segments: for({h, i} <- import_segments, do: {h, de_le(i, 2)}),
       extrinsic: for({h, i} <- extrinsic, do: {h, de_le(i, 4)}),
       export_count: de_le(export_count, 2)
     }, rest}
  end

  # Formula (199) v0.4.5
  def to_work_result(%__MODULE__{} = wi, output) do
    %WorkResult{
      service: wi.service,
      code_hash: wi.code_hash,
      payload_hash: Hash.default(wi.payload),
      gas_ratio: wi.gas_limit,
      result: output
    }
  end

  # Formula (205) v0.4.5
  # X(w ∈ I) ≡ [d ∣ (H(d),∣d∣) −< wx]
  def extrinsic_data(%__MODULE__{} = w, storage) do
    for {r, n} <- w.extrinsic, d = Map.get(storage, r), byte_size(d) == n, do: d
  end

  # Formula (205) v0.4.5
  # S(w ∈ I) ≡ [s[n] ∣ M(s) = L(r),(r,n) <− wi]
  def import_segment_data(%__MODULE__{} = w, s) do
    for {r, n} <- w.import_segments,
        MerkleTree.merkle_root(s) == WorkPackage.segment_root(r),
        do: Enum.at(s, n)
  end

  # Formula (205) v0.4.5
  # J ( w ∈ I ) ≡ [ ↕ J ( s , n ) ∣ M ( s ) = L ( r ) , ( r , n ) <− w i ]
  def segment_justification(%__MODULE__{} = w, s) do
    for {r, n} <- w.import_segments,
        MerkleTree.merkle_root(s) == WorkPackage.segment_root(r),
        do: vs(MerkleTree.justification(s, n))
  end

  use JsonDecoder

  def json_mapping do
    %{extrinsic: &decode_extrinsic/1, import_segments: &decode_import_segments/1}
  end

  def decode_extrinsic(json) do
    for(i <- json, do: {JsonDecoder.from_json(i[:hash]), JsonDecoder.from_json(i[:len])})
  end

  def decode_import_segments(json) do
    for(i <- json, do: {JsonDecoder.from_json(i[:tree_root]), JsonDecoder.from_json(i[:index])})
  end
end
