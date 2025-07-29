defmodule Network.ClientCalls do
  alias Block.Extrinsic.Guarantee.WorkReport
  import Codec.Encoder
  alias Codec.VariableSize
  use Sizes
  @log_context "[QUIC_CLIENT_CALLS]"
  use Util.Logger

  def call(protocol_id, [single_message]) do
    call(protocol_id, single_message)
  end

  def call(128, message) do
    log("Received block response")
    {:ok, Block.decode_list(message)}
  end

  def call(129, [bounderies, trie_bin]) do
    log("Received state response")

    trie =
      Stream.unfold(trie_bin, fn
        <<>> ->
          nil

        <<k::binary-size(31), rest::binary>> ->
          {value, rest} = VariableSize.decode(rest, :binary)
          {{k, value}, rest}
      end)
      |> Enum.into(%{})

    {:ok, {bounderies, trie}}
  end

  def call(134, message) do
    log("Received work report response")
    <<hash::b(hash), signature::b(signature)>> = message
    {:ok, {hash, signature}}
  end

  def call(136, message) when message == <<>>, do: {:error, :not_found}

  def call(136, message) do
    log("Received work report")
    {work_report, <<>>} = WorkReport.decode(message)
    {:ok, work_report}
  end

  def call(137, [bundle_shard, segments, justification]) do
    log("Received shard")
    {:ok, {bundle_shard, segments, justification}}
  end

  def call(138, [bundle_shard, justification]) do
    log("Received shard")
    {:ok, {bundle_shard, justification}}
  end

  def call(139, shards_bin) do
    {:ok, split_shards(shards_bin)}
  end

  def call(140, [shards_bin | justifications]) do
    {:ok, {split_shards(shards_bin), justifications}}
  end

  def call(143, message) do
    case message do
      <<>> ->
        {:error, :not_found}

      _ ->
        log("Received preimage response.")
        Jamixir.NodeAPI.save_preimage(message)
    end
  end

  def call(0, _message) do
    log("Block announcement confirmed")
    :ok
  end

  def call(protocol_id, message) do
    log("Received protocol #{protocol_id} message")
    {:ok, message}
  end

  defp split_shards(shards_bin) do
    shards_bin
    |> :binary.bin_to_list()
    |> Enum.chunk_every(@segment_shard_size)
    |> Enum.map(&:binary.list_to_bin/1)
  end
end
