defmodule Jamixir.SqlStorage do
  @moduledoc """
  SQL-based storage for block extrinsics that require querying capabilities.
  """

  alias Block.Extrinsic.{Assurance, Disputes.Judgement, Guarantee, Preimage}
  alias Jamixir.Repo

  alias Storage.{
    AssuranceRecord,
    AvailabilityRecord,
    GuaranteeRecord,
    JudgementRecord,
    PreimageMetadataRecord
  }

  import Ecto.Query

  def save(%Assurance{} = assurance) do
    attrs = Map.from_struct(assurance)

    %AssuranceRecord{}
    |> AssuranceRecord.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:bitfield, :signature, :updated_at]},
      conflict_target: [:hash, :validator_index]
    )
  end

  def save(%PreimageMetadataRecord{} = p) do
    changeset =
      %PreimageMetadataRecord{}
      |> PreimageMetadataRecord.changeset(Map.from_struct(p))

    case Repo.insert(changeset) do
      {:ok, _record} -> {:ok, p.hash}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def save(%AvailabilityRecord{} = availability) do
    %AvailabilityRecord{}
    |> AvailabilityRecord.changeset(Map.from_struct(availability))
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:shard_index, :bundle_length, :erasure_root, :exports_root, :segment_count, :updated_at]},
      conflict_target: [:work_package_hash]
    )
  end

  def save(%Judgement{} = judgement, hash, epoch) do
    attrs =
      Map.from_struct(judgement)
      |> Map.merge(%{
        work_report_hash: hash,
        epoch: epoch
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
      credentials: Guarantee.encode_credentials(guarantee.credentials)
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

  def get(AvailabilityRecord, hash) do
    Repo.get_by(AvailabilityRecord, work_package_hash: hash)
  end

  def get_all(Assurance) do
    Repo.all(AssuranceRecord) |> Enum.map(&AssuranceRecord.to_assurance/1)
  end

  def get_all(Preimage) do
    Repo.all(PreimageMetadataRecord)
  end

  def get_all(Assurance, hash) do
    Repo.all(from(a in AssuranceRecord, where: a.hash == ^hash))
    |> Enum.map(&AssuranceRecord.to_assurance/1)
  end

  def get_all(Judgement, epoch) do
    Repo.all(from(j in JudgementRecord, where: j.epoch == ^epoch))
    |> Enum.map(&JudgementRecord.to_judgement/1)
  end

  def get_all(Guarantee, status) do
    Repo.all(from(g in GuaranteeRecord, where: g.status == ^status, order_by: g.core_index))
  end

  def get_all(Preimage, status) do
    Repo.all(from(p in PreimageMetadataRecord, where: p.status == ^status))
  end

  def mark_preimage_included(hash, service_id) do
    from(p in PreimageMetadataRecord,
      where: p.hash == ^hash and p.service_id == ^service_id
    )
    |> Repo.update_all(set: [status: :included])
  end

  def mark_included(guarantee_work_report_hashes, header_hash) do
    from(g in GuaranteeRecord,
      where: g.work_report_hash in ^guarantee_work_report_hashes
    )
    |> Repo.update_all(set: [status: :included, included_in_block: header_hash])
  end
end
