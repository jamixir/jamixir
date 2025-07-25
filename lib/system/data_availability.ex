defmodule System.DataAvailability do
  alias Network.Connection
  alias Network.Types.SegmentShardsRequest
  alias Jamixir.NodeStateServer
  require Logger
  @callback do_get_segment(binary(), non_neg_integer()) :: binary()
  @callback do_get_justification(binary(), non_neg_integer()) :: binary()

  def get_segment(merkle_root, segment_index) do
    module = Application.get_env(:jamixir, :data_availability, __MODULE__)

    module.do_get_segment(merkle_root, segment_index)
  end

  def get_justification(merkle_root, segment_index) do
    module = Application.get_env(:jamixir, :data_availability, __MODULE__)
    module.do_get_justification(merkle_root, segment_index)
  end

  def do_get_justification(_merkle_root, _segment_index) do
    # TODO
    <<>>
  end

  def do_get_segment(erasure_root, segment_index) do
    # first try local storage for segment
    case Storage.get_segment(erasure_root, segment_index) do
      nil ->
        core = Storage.get_segment_core(erasure_root)

        {shards, indexes} =
          for {v, pid} <- NodeStateServer.instance().validator_connections() do
            Logger.debug(
              "Requesting segment shards for erasure root #{inspect(erasure_root)} and segment index #{segment_index} from validator #{v.ed25519}"
            )

            shard_index =
              NodeStateServer.instance().assigned_shard_index(core, v.ed25519)

            req = %SegmentShardsRequest{
              erasure_root: erasure_root,
              segment_index: segment_index,
              shard_indexes: [shard_index]
            }

            {:ok, shards} = Connection.request_segment_shards(pid, [req], false)

            {shards, shard_index}
          end
          |> Enum.unzip()

        ErasureCoding.decode(shards, indexes, Constants.segment_size(), Constants.core_count())

      segment ->
        segment
    end
  end
end
