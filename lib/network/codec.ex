defmodule Network.Codec do
  def get_protocol_id(<<protocol_id::8, _::binary>>), do: protocol_id

  def encode_message(message) do
    length = byte_size(message)
    <<length::32-little, message::binary>>
  end

  def encode_message(protocol_id, message) do
    length = byte_size(message)
    <<protocol_id::8, length::32-little, message::binary>>
  end

  def decode_messages(<<>>), do: []

  def decode_messages(<<_protocol_id::8, length::32-little, message::binary-size(length)>>),
    do: [message]

  def decode_messages(
        <<_protocol_id::8, l1::32-little, m1::binary-size(l1), l2::32-little,
          m2::binary-size(l2)>>
      ),
      do: [m1, m2]

  def decode_messages(<<length::32-little, message::binary-size(length)>>), do: [message]
end
