defmodule Network.ClientAPI do
  alias Block.Extrinsic.Assurance
  alias Block.Extrinsic.Disputes.Judgement
  alias Block.Extrinsic.Guarantee
  alias Block.Extrinsic.TicketProof
  alias Block.Extrinsic.WorkPackage
  alias Block.Header
  alias Network.Types.SegmentShardsRequest
  alias System.Audit.AuditAnnouncement

  @callback send(pid(), integer(), binary() | list(binary())) ::
              {:ok, binary()} | {:error, term()}
  @callback request_blocks(pid(), Types.hash(), 0 | 1, integer()) ::
              {:ok, list()} | {:error, term()}
  @callback announce_block(pid(), Header.t(), Types.timeslot()) :: :ok | {:error, term()}
  @callback announce_preimage(pid(), Types.service_index(), Types.hash(), integer()) ::
              :ok | {:error, term()}
  @callback get_preimage(pid(), Types.hash()) :: {:ok, binary()} | {:error, term()}
  @callback distribute_assurance(pid(), Assurance.t()) :: :ok | {:error, term()}
  @callback distribute_ticket(pid(), atom(), Types.epoch_index(), TicketProof.t()) ::
              :ok | {:error, term()}
  @callback announce_judgement(pid(), Types.epoch_index(), Types.hash(), Judgement.t()) ::
              :ok | {:error, term()}
  @callback distribute_guarantee(pid(), Guarantee.t()) :: :ok | {:error, term()}
  @callback get_work_report(pid(), Types.hash()) :: {:ok, WorkReport.t()} | {:error, term()}
  @callback send_work_package(pid(), WorkPackage.t(), integer(), list(binary())) ::
              :ok | {:error, term()}
  @callback send_work_package_bundle(pid(), binary(), integer(), %{Types.hash() => Types.hash()}) ::
              {:ok, {binary(), binary()}} | {:error, term()}
  @callback announce_audit(pid(), AuditAnnouncement.t()) :: :ok | {:error, term()}
  @callback request_work_report_shard(pid(), Hash.t(), integer()) ::
              {:ok, {binary(), list(binary()), list(binary())}} | {:error, term()}
  @callback request_audit_shard(pid(), binary(), integer()) ::
              {:ok, {binary(), list(binary())}} | {:error, term()}
  @callback request_state(pid(), Types.hash(), binary(), binary(), integer()) ::
              {:ok, {list(binary()), map()}} | {:error, term()}
  @callback request_segment_shards(pid(), list(SegmentShardsRequest.t()), boolean()) ::
              {:ok, list(binary())} | {:ok, {list(binary()), list(binary())}} | {:error, term()}
end
