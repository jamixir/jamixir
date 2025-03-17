defmodule Block.Extrinsic.WorkItem do
  @moduledoc """
  Work Item
  Section 14.3
  """
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.DataAvailability
  alias Block.Extrinsic.{Guarantee.WorkResult}
  alias Util.{Hash, MerkleTree}
  use Codec.Encoder
  use Codec.Decoder
  use Sizes
  use AccessStruct

  @type t :: %__MODULE__{
          # s
          service: non_neg_integer(),
          # c
          code_hash: Types.hash(),
          # y
          payload: binary(),
          # g
          refine_gas_limit: non_neg_integer(),
          # a
          accumulate_gas_limit: non_neg_integer(),
          # e
          export_count: non_neg_integer(),
          # i
          # TODO: update the type to be H ∪ (H⊞)
          import_segments: list({Types.hash(), non_neg_integer()}),
          # x
          extrinsic: list({Types.hash(), non_neg_integer()})
        }

  # Formula (14.3) v0.6.0
  defstruct [
    # s: The identifier of the service to which it relates
    service: 0,
    # c: The code hash of the service at the time of reporting
    code_hash: Hash.zero(),
    # y: A payload blob
    payload: <<>>,
    # g: Refinement gas limit
    refine_gas_limit: 0,
    # a: Accumulated gas limit
    accumulate_gas_limit: 0,
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
    # Formula (C.26) v0.6.0
    def encode(%WorkItem{} = wi) do
      Encoder.encode({
        t(wi.service),
        wi.code_hash,
        vs(wi.payload),
        <<wi.refine_gas_limit::64-little>>,
        <<wi.accumulate_gas_limit::64-little>>,
        vs(encode_import_segments(wi)),
        vs(encode_extrinsic(wi)),
        <<wi.export_count::16-little>>
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
    <<service::service(), bin::binary>> = bin
    <<code_hash::b(hash), bin::binary>> = bin
    {payload, bin} = VariableSize.decode(bin, :binary)
    <<refine_gas_limit::64-little, bin::binary>> = bin
    <<accumulate_gas_limit::64-little, bin::binary>> = bin
    {import_segments, bin} = VariableSize.decode(bin, :list_of_tuples, @hash_size, 2)
    {extrinsic, bin} = VariableSize.decode(bin, :list_of_tuples, @hash_size, 4)
    <<export_count::16-little, rest::binary>> = bin

    {%__MODULE__{
       service: service,
       code_hash: code_hash,
       payload: payload,
       refine_gas_limit: refine_gas_limit,
       accumulate_gas_limit: accumulate_gas_limit,
       import_segments: for({h, <<i::16-little>>} <- import_segments, do: {h, i}),
       extrinsic: for({h, <<i::32-little>>} <- extrinsic, do: {h, i}),
       export_count: export_count
     }, rest}
  end

  # Formula (14.8) v0.6.2
  def to_work_result(%__MODULE__{} = wi, output) do
    %WorkResult{
      service: wi.service,
      code_hash: wi.code_hash,
      payload_hash: h(wi.payload),
      gas_ratio: wi.refine_gas_limit,
      result: output
    }
  end

  # Formula (14.14) v0.6.0
  # X(w ∈ I) ≡ [d ∣ (H(d),∣d∣) −< wx]
  def extrinsic_data(%__MODULE__{} = w) do
    for {r, n} <- w.extrinsic, d = Storage.get(r), byte_size(d) == n, do: d
  end

  # Formula (14.14) v0.6.2
  # S(w ∈ I) ≡ [s[n] ∣ M(s) = L(r),(r,n) <− wi]
  def import_segment_data(%__MODULE__{} = w) do
    for {r, n} <- w.import_segments,
        do: DataAvailability.get_segment(WorkReport.segment_root(r), n)
  end

  # Formula (14.14) v0.6.0
  # J ( w ∈ I ) ≡ [ ↕ J0 ( s , n ) ∣ M ( s ) = L ( r ) , ( r , n ) <− w i ]
  def segment_justification(%__MODULE__{} = w) do
    for {r, n} <- w.import_segments,
        s = DataAvailability.get_segment(WorkReport.segment_root(r), n),
        do: vs(MerkleTree.justification(s, n, 0))
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
