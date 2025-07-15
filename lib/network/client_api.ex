defmodule Network.ClientAPI do
  @callback send(pid(), integer(), binary()) :: {:ok, binary()} | {:error, term()}
  @callback request_blocks(pid(), binary(), atom(), integer()) :: {:ok, list()} | {:error, term()}
  @callback announce_block(pid(), map(), integer()) :: :ok | {:error, term()}
  @callback announce_preimage(pid(), integer(), binary(), integer()) :: :ok | {:error, term()}
  @callback get_preimage(pid(), binary()) :: {:ok, binary()} | {:error, term()}
  @callback distribute_assurance(pid(), map()) :: :ok | {:error, term()}
  @callback distribute_ticket(pid(), atom(), integer(), map()) :: :ok | {:error, term()}
  @callback announce_judgement(pid(), integer(), binary(), map()) :: :ok | {:error, term()}
  @callback distribute_guarantee(pid(), map()) :: :ok | {:error, term()}
  @callback get_work_report(pid(), binary()) :: {:ok, map()} | {:error, term()}
  @callback send_work_package(pid(), map(), integer(), list()) :: :ok | {:error, term()}
  @callback send_work_package_bundle(pid(), binary(), integer(), map()) ::
              {:ok, {binary(), binary()}} | {:error, term()}
  @callback announce_audit(pid(), map()) :: :ok | {:error, term()}
  @callback request_work_report_shard(pid(), binary(), integer()) ::
              {:ok, {binary(), list(), list()}} | {:error, term()}
  @callback request_audit_shard(pid(), binary(), integer()) ::
              {:ok, {binary(), list()}} | {:error, term()}
  @callback request_state(pid(), binary(), binary(), binary(), integer()) ::
              {:ok, {list(), map()}} | {:error, term()}
  @callback request_segment_shards(pid(), list(), boolean()) ::
              {:ok, list()} | {:ok, {list(), list()}} | {:error, term()}
end
