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

  def decode_message(<<_protocol_id::8, length::32-little, message::binary-size(length)>>),
    do: message

  def decode_message(<<length::32-little, message::binary-size(length)>>), do: message
end
