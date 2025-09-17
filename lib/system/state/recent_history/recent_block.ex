defmodule System.State.RecentHistory.RecentBlock do
  alias Util.Hash

  @type t :: %__MODULE__{
          # h
          header_hash: Types.hash(),
          # b
          beefy_root: Types.hash(),
          # s
          state_root: Types.hash(),
          # p
          work_report_hashes: %{Types.hash() => Types.hash()}
        }

  # Formula (7.2) v0.7.2
  # βH ∈ ⟦(h ∈ H, s ∈ H, b ∈ H, p ∈ H → H)⟧∶H
  # h
  defstruct header_hash: Hash.zero(),
            # b
            beefy_root: Hash.zero(),
            # s
            state_root: Hash.zero(),
            # p
            work_report_hashes: %{}

  use JsonDecoder

  def json_mapping,
    do: %{
      work_report_hashes: [&map_reported_hashes/1, :reported]
    }

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

  defimpl Encodable do
    import Codec.Encoder, only: [e: 1]
    alias System.State.RecentHistory.RecentBlock

    def encode(%RecentBlock{} = b) do
      e({b.header_hash, b.beefy_root, b.state_root, b.work_report_hashes})
    end
  end

  use Sizes
  import Codec.Encoder

  def decode(bin) do
    <<header_hash::b(hash), rest::binary>> = bin
    <<beefy_root::b(hash), rest::binary>> = rest
    <<state_root::b(hash), rest::binary>> = rest
    {work_report_hashes, rest} = Codec.VariableSize.decode(rest, :map, @hash_size, @hash_size)

    {%__MODULE__{
       header_hash: header_hash,
       beefy_root: beefy_root,
       state_root: state_root,
       work_report_hashes: work_report_hashes
     }, rest}
  end

  def to_json_mapping do
    %{
      work_report_hashes:
        {:reported,
         &for {hash, exports_root} <- &1 do
           %{hash: hash, exports_root: exports_root}
         end}
    }
  end
end
