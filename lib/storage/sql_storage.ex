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
    PreimageMetadataRecord,
    BlockRecord
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

  def save_block(header_hash, parent_header_hash, slot) do
    %BlockRecord{}
    |> BlockRecord.changeset(%{
      header_hash: header_hash,
      parent_header_hash: parent_header_hash,
      slot: slot
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: :header_hash,
      returning: [:header_hash]
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

  @doc """
  Get the canonical root hash of the tip and the applied block
  we walk down the chain, starting from a tip (which is a none applied incoming block)
  and we stop when we find the first applied block.
  the first applied block is the canonical root.
  """
  def get_canonical_root(tip_hash) do
    # Encode hash as hex for SQLite binary comparison
    # SQLite's ? placeholder doesn't properly bind binary data, so we use hex encoding
    # SQLite's hex() function returns UPPERCASE, so we must use uppercase for comparison
    tip_hash_hex = Base.encode16(tip_hash, case: :upper)

    sql = """
    WITH RECURSIVE chain AS (
      SELECT header_hash, parent_header_hash, applied, 0 AS depth
      FROM blocks
      WHERE hex(header_hash) = ?

      UNION ALL

      SELECT b.header_hash, b.parent_header_hash, b.applied, c.depth + 1 AS depth
      FROM blocks b
      JOIN chain c
      ON hex(b.header_hash) = hex(c.parent_header_hash)
    )
    SELECT header_hash
    FROM chain
    WHERE applied = 1
    ORDER BY depth ASC
    LIMIT 1;
    """

    case Repo.query(sql, [tip_hash_hex]) do
      {:ok, %{rows: [[header_hash]]}} ->
        {:ok, header_hash}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  this is the fork choice rule, the fork that has the most blocks in it, from the canonical root.
  until the edge of the DAG, is the heaviest
  this is the fork we need to keep.
  """
  def get_heaviest_chain_tip_from_canonical_root(canonical_root) do
    canonical_root_hex = Base.encode16(canonical_root, case: :upper)

    sql = """
    WITH RECURSIVE forward AS (
      SELECT header_hash, parent_header_hash, 0 AS depth
      FROM blocks
      WHERE hex(header_hash) = ?

      UNION ALL

      SELECT c.header_hash, c.parent_header_hash, f.depth + 1
      FROM blocks c
      JOIN forward f
        ON hex(c.parent_header_hash) = hex(f.header_hash)
    )
    SELECT header_hash
    FROM forward
    ORDER BY depth DESC
    LIMIT 1;
    """

    case Repo.query(sql, [canonical_root_hex]) do
      {:ok, %{rows: [[hash]]}} -> {:ok, hash}
      {:ok, %{rows: []}} -> :not_found
      error -> error
    end
  end

  def mark_applied(header_hash) do
    from(b in BlockRecord,
      where: b.header_hash == ^header_hash
    )
    |> Repo.update_all(set: [applied: true])
  end

  @doc """
  Unmark blocks between two points in the chain (inclusive of start, exclusive of end).
  This walks the chain from start_hash backwards to end_hash and marks them as not applied.
  Used during chain reorganization to unmark the old canonical chain.
  """
  def unmark_between(start_hash, end_hash) do
    start_hash_hex = Base.encode16(start_hash, case: :upper)
    end_hash_hex = Base.encode16(end_hash, case: :upper)

    sql = """
    WITH RECURSIVE chain AS (
      SELECT header_hash, parent_header_hash
      FROM blocks
      WHERE hex(header_hash) = ?

      UNION ALL

      SELECT b.header_hash, b.parent_header_hash
      FROM blocks b
      JOIN chain c
      ON hex(b.header_hash) = hex(c.parent_header_hash)
      WHERE hex(b.header_hash) != ?
    )
    UPDATE blocks
    SET applied = 0
    WHERE header_hash IN (
      SELECT header_hash
      FROM chain
      WHERE hex(header_hash) != ?
    );
    """

    case Repo.query(sql, [start_hash_hex, end_hash_hex, end_hash_hex]) do
      {:ok, _} ->
        :ok

      error ->
        error
    end
  end

  @doc """
  Get all header hashes in a chain from root (exclusive) to tip (inclusive).
  Returns hashes in application order (oldest first, closest to root).
  """
  def get_chain_hashes(root_hash, tip_hash) do
    root_hex = Base.encode16(root_hash, case: :upper)
    tip_hex = Base.encode16(tip_hash, case: :upper)

    sql = """
    WITH RECURSIVE chain AS (
      SELECT header_hash, parent_header_hash, 0 AS depth
      FROM blocks
      WHERE hex(header_hash) = ?

      UNION ALL

      SELECT b.header_hash, b.parent_header_hash, c.depth + 1
      FROM blocks b
      JOIN chain c
      ON hex(b.header_hash) = hex(c.parent_header_hash)
      WHERE hex(b.header_hash) != ?
    )
    SELECT header_hash
    FROM chain
    WHERE hex(header_hash) != ?
    ORDER BY depth DESC;
    """

    case Repo.query(sql, [tip_hex, root_hex, root_hex]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [hash] -> hash end)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
