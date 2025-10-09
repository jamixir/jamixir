defmodule Storage.JudgementRecord do
  use Ecto.Schema
  import Ecto.Changeset
  alias Block.Extrinsic.Disputes.Judgement

  @primary_key false
  @field_names (Judgement.__struct__()
                |> Map.keys()
                |> Enum.reject(&(&1 == :__struct__))) ++ [:epoch, :work_report_hash]

  schema "judgements" do
    field(:epoch, :integer, primary_key: true)
    field(:work_report_hash, :binary, primary_key: true)
    field(:validator_index, :integer, primary_key: true)
    field(:signature, :binary)
    field(:vote, :boolean)
    timestamps(type: :utc_datetime)
  end

  def changeset(judgement, attrs) do
    judgement
    |> cast(attrs, @field_names)
    |> validate_required(@field_names)
    |> validate_number(:validator_index, greater_than_or_equal_to: 0)
  end

  def to_judgement(%__MODULE__{} = record) do
    struct(Judgement, Map.from_struct(record))
  end
end
