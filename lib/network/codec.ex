defmodule Network.Codec do
  alias Util.Logger

  def encode_message(message) when is_binary(message) do
    length = byte_size(message)
    <<length::32-little, message::binary>>
  end

  def encode_message(msg) when is_list(msg) do
    msg = Enum.join(msg, <<>>)
    encode_message(msg)
  end

  def decode_messages(<<>>), do: []
  def decode_messages(data), do: decode_messages([], data)
  defp decode_messages(acc, <<>>), do: Enum.reverse(acc)

  defp decode_messages(_acc, <<len::32-little, rest::binary>>) when byte_size(rest) < len do
    # Not enough data to read full message
    {:need_more, <<len::32-little, rest::binary>>}
  end

  defp decode_messages(acc, <<len::32-little, rest::binary>>) when byte_size(rest) >= len do
    <<msg::binary-size(len), remaining::binary>> = rest
    decode_messages([msg | acc], remaining)
  end

  defp decode_messages(_acc, malformed) do
    Logger.error("Malformed message or unsupported format: #{inspect(malformed)}")
    []
  end
end
