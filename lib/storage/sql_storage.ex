defmodule Jamixir.SqlStorage do
  @moduledoc """
  SQL-based storage for block extrinsics that require querying capabilities.
  """

  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Disputes.Judgement
  alias Jamixir.Repo
  alias Storage.{AssuranceRecord, GuaranteeRecord, JudgementRecord}
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

  def save(%Guarantee{} = guarantee, wr_hash) do
    %GuaranteeRecord{}
    |> GuaranteeRecord.changeset(%{
      work_report_hash: wr_hash,
      core_index: guarantee.work_report.core_index,
      timeslot: guarantee.timeslot,
      credentials: Guarantee.encode_credentials(guarantee.credentials),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    })
    |> Repo.insert!(
      on_conflict: :replace_all,
      conflict_target: :core_index
    )
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

  def list_guarantee_candidates() do
    Repo.all(from(g in GuaranteeRecord, where: g.status == :pending, order_by: g.core_index))
  end

  def mark_included(guarantee_work_report_hashes, block_hash) do
    from(g in GuaranteeRecord,
      where: g.work_report_hash in ^guarantee_work_report_hashes
    )
    |> Repo.update_all(set: [status: :included, included_in_block: block_hash])
  end

  def mark_rejected(guarantee_work_report_hashes) do
    from(g in GuaranteeRecord,
      where: g.work_report_hash in ^guarantee_work_report_hashes
    )
    |> Repo.update_all(set: [status: :rejected])
  end
end
