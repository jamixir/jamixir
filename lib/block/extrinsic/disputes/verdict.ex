defmodule Block.Extrinsic.Disputes.Verdict do
  alias Block.Extrinsic.Disputes.Judgement
  alias Types

  # Formula (10.2) v0.7.2
  # Formula (10.9) v0.7.2
  @type t :: %__MODULE__{
          # r
          work_report_hash: Types.hash(),
          # a
          epoch_index: Types.epoch_index(),
          # j
          judgements: list(Judgement.t())
        }

  defstruct work_report_hash: <<>>, epoch_index: 0, judgements: []

  # Formula (10.12) v0.7.2
  def sum_judgements(%__MODULE__{judgements: j}) do
    Enum.reduce(j, 0, &if(&1.vote, do: &2 + 1, else: &2))
  end

  defimpl Encodable do
    import Codec.Encoder, only: [e: 1, e_le: 2]
    alias Block.Extrinsic.Disputes.Verdict

    def encode(%Verdict{} = v) do
      e({v.work_report_hash, e_le(v.epoch_index, 4), v.judgements})
    end
  end

  import Codec.Encoder, only: [b: 1, m: 1]

  @judgements_count div(2 * Constants.validator_count(), 3) + 1
  @judgements_size Judgement.size() * @judgements_count
  def judgements_count, do: @judgements_count

  def decode(bin) do
    <<work_report_hash::b(hash), epoch_index::m(epoch),
      judgements_bin::binary-size(@judgements_size), rest::binary>> = bin

    {judgements, _} =
      Enum.reduce(1..@judgements_count, {[], judgements_bin}, fn _, {list, bin} ->
        {judgement, rest} = Judgement.decode(bin)
        {list ++ [judgement], rest}
      end)

    {
      %__MODULE__{
        work_report_hash: work_report_hash,
        epoch_index: epoch_index,
        judgements: judgements
      },
      rest
    }
  end

  use JsonDecoder

  def json_mapping,
    do: %{work_report_hash: :target, epoch_index: :age, judgements: [[Judgement], :votes]}
end
