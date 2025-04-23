defmodule Network.Codec do
  def get_protocol_id(<<protocol_id::8, _::binary>>), do: protocol_id

  def encode_message(message) when is_binary(message) do
    length = byte_size(message)
    <<length::32-little, message::binary>>
  end

  def encode_message(msg) when is_list(msg) do
    msg = Enum.join(msg, <<>>)
    encode_message(msg)
  end

  def encode_message(protocol_id, message) do
    length = byte_size(message)
    <<protocol_id::8, length::32-little, message::binary>>
  end

  def decode_messages(<<>>), do: []

  def decode_messages(data) do
    decode_messages([], data)
  end

  # reversed because we were prepending the messages: [msg | acc]
  defp decode_messages(acc, <<>>), do: Enum.reverse(acc)

  defp decode_messages(acc, <<len::32-little, rest::binary>>) when byte_size(rest) < len do
    {:need_more, <<len::32-little, rest::binary>>}
  end

  defp decode_messages(acc, <<len::32-little, msg::binary-size(len), rest::binary>>) do
    decode_messages([msg | acc], rest)
  end

  # def decode_messages(<<>>), do: []

  # def decode_messages(<<_protocol_id::8, length::32-little, message::binary-size(length)>>),
  #   do: [message]

  # def decode_messages(
  #       <<_protocol_id::8, l1::32-little, m1::binary-size(l1), l2::32-little,
  #         m2::binary-size(l2)>>
  #     ),
  #     do: [m1, m2]

  # def decode_messages(<<length::32-little, message::binary-size(length)>>), do: [message]
end
