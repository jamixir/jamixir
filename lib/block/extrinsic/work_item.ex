defmodule Block.Extrinsic.WorkItem do
  @moduledoc """
  Work Item
  Section 14.3
  """
  alias System.DataAvailability.SegmentData
  alias Block.Extrinsic.Guarantee.WorkExecutionError
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.DataAvailability
  alias Block.Extrinsic.{Guarantee.WorkDigest}
  alias Util.Hash
  import Codec.{Encoder, Decoder}
  alias Codec.VariableSize
  use Sizes
  use AccessStruct
  import Bitwise, only: [&&&: 2]

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
          import_segments: list({Types.segment_ref(), non_neg_integer()}),
          # x
          extrinsic: list({Types.hash(), non_neg_integer()})
        }

  # Formula (14.3) v0.7.0 - W
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
    import Codec.Encoder
    # Formula (C.29) v0.7.0
    def encode(%WorkItem{} = wi) do
      e({
        t(wi.service),
        wi.code_hash,
        <<wi.refine_gas_limit::m(gas)>>,
        <<wi.accumulate_gas_limit::m(gas)>>,
        <<wi.export_count::m(segment_count)>>,
        vs(wi.payload),
        vs(encode_import_segments(wi)),
        vs(encode_extrinsic(wi))
      })
    end

    # Formula (C.34) v0.7.0
    defp encode_import_segments(work_item) do
      for {h, i} <- work_item.import_segments,
          do: {Types.hash(h), <<i + if(Types.tagged?(h), do: 0x8000, else: 0)::m(segment_count)>>}
    end

    defp encode_extrinsic(work_item) do
      for {h, i} <- work_item.extrinsic, do: {h, e_le(i, 4)}
    end
  end

  def encode(%__MODULE__{} = wi, :fetch_host_call) do
    e({
      t(wi.service),
      wi.code_hash,
      <<wi.refine_gas_limit::m(gas)>>,
      <<wi.accumulate_gas_limit::m(gas)>>,
      <<wi.export_count::m(segment_count)>>,
      <<length(wi.import_segments)::m(segment_count)>>,
      <<length(wi.extrinsic)::m(segment_count)>>,
      <<byte_size(wi.payload)::32-little>>
    })
  end

  defp decode_import_segments_binary(segments) do
    for {hash, index} <- segments do
      tag = if (de_le(index, 2) &&& 0x8000) != 0, do: :tagged_hash, else: :hash

      index = de_le(index, 2) &&& 0x7FFF

      case tag do
        :tagged_hash -> {{:tagged_hash, hash}, index}
        :hash -> {hash, index}
      end
    end
  end

  def decode(bin) do
    <<service::service(), bin::binary>> = bin
    <<code_hash::b(hash), bin::binary>> = bin
    <<refine_gas_limit::m(gas), bin::binary>> = bin
    <<accumulate_gas_limit::m(gas), bin::binary>> = bin
    <<export_count::m(segment_count), bin::binary>> = bin
    {payload, bin} = VariableSize.decode(bin, :binary)
    {import_segments, bin} = VariableSize.decode(bin, :list_of_tuples, @hash_size, 2)
    {extrinsic, rest} = VariableSize.decode(bin, :list_of_tuples, @hash_size, 4)

    import_segments = decode_import_segments_binary(import_segments)

    {%__MODULE__{
       service: service,
       code_hash: code_hash,
       payload: payload,
       refine_gas_limit: refine_gas_limit,
       accumulate_gas_limit: accumulate_gas_limit,
       import_segments: import_segments,
       extrinsic: for({h, <<i::32-little>>} <- extrinsic, do: {h, i}),
       export_count: export_count
     }, rest}
  end

  # Formula (14.9) v0.7.0
  @spec to_work_digest(
          Block.Extrinsic.WorkItem.t(),
          binary() | WorkExecutionError.t(),
          Types.gas()
        ) ::
          Block.Extrinsic.Guarantee.WorkDigest.t()
  def to_work_digest(%__MODULE__{} = wi, result, gas) do
    %WorkDigest{
      service: wi.service,
      code_hash: wi.code_hash,
      payload_hash: h(wi.payload),
      gas_ratio: wi.refine_gas_limit,
      result: result,
      gas_used: gas,
      imports: length(wi.import_segments),
      exports: wi.export_count,
      extrinsic_count: length(wi.extrinsic),
      extrinsic_size: Enum.sum(for {_, n} <- wi.extrinsic, do: n)
    }
  end

  # Formula (14.14) v0.7.0
  # X(w ∈ W) ≡ [d ∣ (H(d),∣d∣) −< wx]
  def extrinsic_data(%__MODULE__{} = w) do
    for {r, n} <- w.extrinsic, d = Storage.get(r), byte_size(d) == n, do: d
  end

  # Formula (14.15) v0.7.0
  # S(w ∈ W) ≡ [b[n] ∣ M(b) = L(r),(r,n) <− wi]
  def import_segment_data(%__MODULE__{} = w) do
    for {r, n} <- w.import_segments,
        root = WorkReport.segment_root(r),
        data = DataAvailability.get_segment(root, n),
        do: %SegmentData{erasure_root: root, segment_index: n, data: data}
  end

  # Formula (14.15) v0.7.0
  # J (w ∈ W) ≡ [↕J0(b,n) ∣ M(b) = L(r), (r,n) <− wi]
  def segment_justification(%__MODULE__{} = w) do
    for {r, n} <- w.import_segments,
        do: DataAvailability.get_justification(WorkReport.segment_root(r), n)
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
