defmodule Network.ClientCalls do
  alias Block.Extrinsic.Guarantee.WorkReport
  require Logger

  def log(message), do: Logger.log(:info, "[QUIC_CLIENT_CALLS] #{message}")

  def call(128, message) do
    log("Received block response")
    {:ok, Block.decode_list(message)}
  end

  def call(136, message) when message == <<>>, do: {:error, :not_found}

  def call(136, message) do
    log("Received work report")
    {work_report, <<>>} = WorkReport.decode(message)
    {:ok, work_report}
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
end
