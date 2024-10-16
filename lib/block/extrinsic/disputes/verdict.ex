defmodule Block.Extrinsic.Disputes.Verdict do
  @moduledoc """
  Formula (98) v0.4.1
  verdic on the correctness of a work-report.
  the Dispute extrinsic Ed may contain 1 or more verdicts. secion 10.2
  A verdict consists of a work-report hash, an epoch index, and a list of judgements from validators.
  """

  alias Block.Extrinsic.Disputes.Judgement
  alias Types

  @type t :: %__MODULE__{
          # r
          work_report_hash: Types.hash(),
          # a
          epoch_index: Types.epoch_index(),
          # j
          judgements: list(Judgement.t())
        }

  defstruct work_report_hash: <<>>, epoch_index: 0, judgements: []

  # Formula (108) v0.4.1
  def sum_judgements(%__MODULE__{judgements: j}) do
    Enum.reduce(j, 0, &if(&1.vote, do: &2 + 1, else: &2))
  end

  defimpl Encodable do
    use Codec.Encoder
    alias Block.Extrinsic.Disputes.Verdict

    def encode(v = %Verdict{}) do
      e({v.work_report_hash, e_le(v.epoch_index, 4), v.judgements})
    end
  end

  use Sizes
  use Codec.Decoder

  def decode(blob) do
    <<work_report_hash::binary-size(@hash_size), epoch_index::binary-size(4), rest::binary>> =
      blob

    {
      %Block.Extrinsic.Disputes.Verdict{
        work_report_hash: work_report_hash,
        epoch_index: de_le(epoch_index, 4)
      },
      rest
    }
  end

  use JsonDecoder

  def json_mapping,
    do: %{work_report_hash: :target, epoch_index: :age, judgements: [[Judgement], :votes]}
end
