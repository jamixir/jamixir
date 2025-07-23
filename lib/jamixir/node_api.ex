defmodule Jamixir.NodeAPI do
  alias System.State
  alias Block.Extrinsic.Disputes.Judgement
  alias Block.Extrinsic.{Assurance, TicketProof, WorkPackage}
  alias Block.Extrinsic.Guarantee
  alias System.Audit.AuditAnnouncement
  @callback add_block(binary) :: {:ok, State.t(), binary()} | {:error, any}
  @callback inspect_state(Types.hash()) :: {:ok, any} | {:error, any}
  @callback inspect_state(Types.hash(), any()) ::
              {:error, :key_not_found | :no_state} | {:ok, any()}
  @callback get_blocks(Types.hash(), :asc | :desc, integer()) ::
              {:ok, list(Block.t())} | {:error, any}
  # CE 131/132 Safrole ticket distribution (epoch index, attempt, proof)
  @callback add_ticket(
              Types.epoch_index(),
              integer(),
              Types.bandersnatch_ringVRF_proof_of_knowledge()
            ) :: :ok | {:error, any}
  # CE 133 - Work-package submission (core index, WP, extrinsic data)
  @callback receive_preimage(Types.service_index(), Types.hash(), non_neg_integer()) ::
              :ok | {:error, any}
  @callback get_preimage(Types.hash()) :: {:ok, binary} | {:error, any}
  @callback save_preimage(binary()) :: :ok | {:error, any}
  @callback process_ticket(:proxy | :validator, Types.epoch_index(), TicketProof.t()) ::
              :ok | {:error, any}
  @callback save_assurance(Assurance.t()) :: :ok | {:error, any}
  @callback save_judgement(Types.epoch_index(), Types.hash(), Judgement.t()) ::
              :ok | {:error, any}
  @callback save_guarantee(Guarantee.t()) :: :ok | {:error, any}
  @callback get_work_report(Types.hash()) :: {:ok, binary} | {:error, any}
  @callback save_work_package(WorkPackage.t(), non_neg_integer(), list(binary())) ::
              :ok | {:error, any}
  @callback save_work_package_bundle(binary(), non_neg_integer(), %{Types.hash() => Types.hash()}) ::
              {:ok, {Types.hash(), Types.ed25519_signature()}} | {:error, any}
  @callback save_audit(AuditAnnouncement.t()) :: :ok | {:error, any}
  @callback get_work_report_shard(Types.hash(), non_neg_integer()) ::
              {:ok, {binary(), list(binary()), binary()}} | {:error, any}
  @callback get_segment_shards(Types.hash(), non_neg_integer(), list(non_neg_integer())) ::
              {:ok, list(binary())} | {:error, any}
  @callback get_state_trie(Types.hash()) :: {:ok, %{binary() => binary()}} | {:error, any}
  @callback get_justification(Types.hash(), non_neg_integer(), non_neg_integer()) ::
              {:ok, binary()} | {:error, any}
  def add_block(a), do: impl().add_block(a)
  def inspect_state, do: impl().inspect_state()
  def inspect_state(a), do: impl().inspect_state(a)
  def get_blocks(hash, order, count), do: impl().get_blocks(hash, order, count)
  def add_ticket(epoch, attempt, proof), do: impl().add_ticket(epoch, attempt, proof)
  def receive_preimage(service, hash, length), do: impl().receive_preimage(service, hash, length)
  def get_preimage(hash), do: impl().get_preimage(hash)
  def save_preimage(preimage), do: impl().save_preimage(preimage)
  def save_assurance(assurance), do: impl().save_assurance(assurance)
  def process_ticket(mode, epoch, ticket), do: impl().process_ticket(mode, epoch, ticket)
  def save_judgement(epoch, hash, judgement), do: impl().save_judgement(epoch, hash, judgement)
  def save_guarantee(guarantee), do: impl().save_guarantee(guarantee)
  def get_work_report(hash), do: impl().get_work_report(hash)
  def save_work_package(wp, core, extrinsic), do: impl().save_work_package(wp, core, extrinsic)
  def save_audit(audit), do: impl().save_audit(audit)

  def get_work_report_shard(erasure_root, segment_index),
    do: impl().get_work_report_shard(erasure_root, segment_index)

  def get_segment_shards(erasure_root, segment_index, share_index),
    do: impl().get_segment_shards(erasure_root, segment_index, share_index)

  def save_work_package_bundle(bundle, core, segment_lookup_dict),
    do: impl().save_work_package_bundle(bundle, core, segment_lookup_dict)

  def get_state_trie(header_hash), do: impl().get_state_trie(header_hash)

  def get_justification(erasure_root, segment_index, shard_index),
    do: impl().get_justification(erasure_root, segment_index, shard_index)

  defp impl, do: Application.get_env(:jamixir, NodeAPI, Jamixir.Node)
end
