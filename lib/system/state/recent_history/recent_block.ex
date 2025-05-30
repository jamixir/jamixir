defmodule System.State.RecentHistory.RecentBlock do
  alias Codec.Decoder

  @type t :: %__MODULE__{
          # h
          header_hash: Types.hash(),
          # b
          accumulated_result_mmr: list(Types.hash() | nil),
          # s
          state_root: Types.hash(),
          # p
          work_report_hashes: %{Types.hash() => Types.hash()}
        }

  # Formula (7.1) v0.6.5
  defstruct header_hash: nil,
            accumulated_result_mmr: [nil],
            state_root: nil,
            work_report_hashes: %{}

  use JsonDecoder

  def json_mapping,
    do: %{
      accumulated_result_mmr: [&mmr/1, :mmr],
      work_report_hashes: [&map_reported_hashes/1, :reported]
    }

  defp mmr(json), do: JsonDecoder.from_json(json[:peaks])

  defp map_reported_hashes(json) do
    for report <- json, into: %{} do
      {f1, f2} =
        if(report[:hash] != nil,
          do: {:hash, :exports_root},
          else: {:work_package_hash, :segment_tree_root}
        )

      {JsonDecoder.from_json(report[f1]), JsonDecoder.from_json(report[f2])}
    end
  end

  use Sizes
  use Codec.Encoder

  def decode(bin) do
    <<header_hash::b(hash), rest::binary>> = bin
    {accumulated_result_mmr, rest} = Decoder.decode_mmr(rest)
    <<state_root::b(hash), rest::binary>> = rest
    {work_report_hashes, rest} = Codec.VariableSize.decode(rest, :map, @hash_size, @hash_size)

    {%__MODULE__{
       header_hash: header_hash,
       accumulated_result_mmr: accumulated_result_mmr,
       state_root: state_root,
       work_report_hashes: work_report_hashes
     }, rest}
  end

  def to_json_mapping do
    %{
      accumulated_result_mmr: :mmr,
      work_report_hashes:
        {:reported,
         &for {hash, exports_root} <- &1 do
           %{hash: hash, exports_root: exports_root}
         end}
    }
  end
end
