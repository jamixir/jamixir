defmodule Jamixir.SqlStorage do
  @moduledoc """
  SQL-based storage for block extrinsics that require querying capabilities.
  """

  alias Block.Extrinsic.Disputes.Judgement
  alias Jamixir.Repo
  alias Storage.AssuranceRecord
  alias Storage.JudgementRecord
  alias Block.Extrinsic.Assurance
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
    |> Repo.insert()
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

  def get_all(Assurance) do
    Repo.all(AssuranceRecord) |> Enum.map(&AssuranceRecord.to_assurance/1)
  end

  def get_all(Judgement, epoch) do
    Repo.all(from(j in JudgementRecord, where: j.epoch == ^epoch))
    |> Enum.map(&JudgementRecord.to_judgement/1)
  end
end
