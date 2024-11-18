defmodule System.State.RecentHistory.RecentBlock do
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

  # Formula (81) v0.4.5
  defstruct header_hash: nil,
            accumulated_result_mmr: [nil],
            state_root: nil,
            work_report_hashes: %{}

  use JsonDecoder

  def json_mapping do
    %{
      header_hash: :hash,
      # This maps json["mmr"]["peaks"] to accumulated_result_mmr
      accumulated_result_mmr: [&mmr/1, :mmr],
      work_report_hashes: [&map_reported_hashes/1, :reported]
    }
  end

  defp mmr(json) do
    JsonDecoder.from_json(json[:peaks])
  end

  defp map_reported_hashes(json) do
    for report <- json,
        into: %{} do
      {
        JsonDecoder.from_json(report[:hash]),
        JsonDecoder.from_json(report[:exports_root])
      }
    end
  end
end
