defmodule Jamixir.SqlStorage do
  @moduledoc """
  SQL-based storage for block extrinsics that require querying capabilities.
  """

  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Disputes.Judgement
  alias Jamixir.Repo
  alias Storage.AssuranceRecord
  alias Storage.JudgementRecord
  import Ecto.Query

  def save(%Assurance{} = assurance) do
    attrs =
      Map.from_struct(assurance)
      |> Map.merge(%{
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

    %AssuranceRecord{}
    |> AssuranceRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:bitfield, :signature, :updated_at]},
      conflict_target: [:hash, :validator_index]
    )
  end

  def save(%Judgement{} = judgement, hash, epoch) do
    attrs =
      Map.from_struct(judgement)
      |> Map.merge(%{
        work_report_hash: hash,
        epoch: epoch,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })

    %JudgementRecord{}
    |> JudgementRecord.changeset(attrs)
    |> Repo.insert()
  end

  def clean(Assurance), do: Repo.delete_all(AssuranceRecord)

  def get(Assurance, [hash, validator_index]) do
    case Repo.get_by(AssuranceRecord, hash: hash, validator_index: validator_index) do
      nil -> nil
      record -> AssuranceRecord.to_assurance(record)
    end
  end

  def get_all(Assurance, hash) do
    Repo.all(from(a in AssuranceRecord, where: a.hash == ^hash))
    |> Enum.map(&AssuranceRecord.to_assurance/1)
  end

  def get_all(Assurance) do
    Repo.all(AssuranceRecord) |> Enum.map(&AssuranceRecord.to_assurance/1)
  end

  def get_all(Judgement, epoch) do
    Repo.all(from(j in JudgementRecord, where: j.epoch == ^epoch))
    |> Enum.map(&JudgementRecord.to_judgement/1)
  end
end
