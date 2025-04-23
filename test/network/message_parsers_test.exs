defmodule Network.MessageParsersTest do
  use ExUnit.Case
  alias Network.MessageParsers

  # Add @log_context to avoid undefined error, as it's used in MessageParsers
  @log_context "[TEST]"

  describe "parse_ce_messages/1" do
    test "handles single message correctly" do
      # Create a single CE message with format: <<length::32-little, message::binary>>
      message = "test message"
      message_length = byte_size(message)
      data = <<message_length::32-little>> <> message

      # Parse the message
      result = MessageParsers.parse_ce_messages(data)

      # Verify results
      assert length(result) == 1
      assert hd(result) == message
    end

    test "handles multiple messages correctly" do
      # Create multiple CE messages
      message1 = "first message"
      message2 = "second longer message"
      message3 = "third and final message"

      message1_length = byte_size(message1)
      message2_length = byte_size(message2)
      message3_length = byte_size(message3)

      # Combine into a single binary with length prefixes
      data = <<
        message1_length::32-little, message1::binary,
        message2_length::32-little, message2::binary,
        message3_length::32-little, message3::binary
      >>

      # Parse the messages
      result = MessageParsers.parse_ce_messages(data)

      # Verify results
      assert length(result) == 3
      assert Enum.at(result, 0) == message1
      assert Enum.at(result, 1) == message2
      assert Enum.at(result, 2) == message3
    end

    test "handles empty buffer" do
      # Test with an empty buffer
      result = MessageParsers.parse_ce_messages(<<>>)

      # Should return an empty list
      assert result == []
    end

    test "handles malformed buffer" do
      # Malformed buffer without proper length header
      malformed_data = <<"incomplete">>

      # Should return an empty list and not crash
      result = MessageParsers.parse_ce_messages(malformed_data)
      assert result == []
    end

    test "handles incomplete message" do
      # Incomplete message where the length is specified but not enough data follows
      message_length = 20
      incomplete_data = <<message_length::32-little, "only 10 bytes"::binary>>

      # Should handle gracefully and return empty list
      result = MessageParsers.parse_ce_messages(incomplete_data)
      assert result == []
    end
  end

  describe "parse_up_message/1" do
    test "handles complete message" do
      # Create UP message: <<protocol_id::8, length::32-little, message::binary>>
      protocol_id = 42
      message = "test up message"
      message_length = byte_size(message)
      data = <<protocol_id::8, message_length::32-little, message::binary>>

      # Parse the message
      result = MessageParsers.parse_up_message(data)

      # Verify complete message is detected and returned
      assert {:complete, ^message, <<>>} = result
    end

    test "handles complete message with remaining data" do
      # Message with additional data after it
      protocol_id = 42
      message = "complete message"
      message_length = byte_size(message)
      remaining = "additional data"

      data = <<protocol_id::8, message_length::32-little, message::binary, remaining::binary>>

      # Parse the message
      result = MessageParsers.parse_up_message(data)

      # Should return the complete message and the remaining data
      assert {:complete, ^message, ^remaining} = result
    end

    test "handles incomplete message" do
      # Incomplete message: header is present but not enough data
      protocol_id = 42
      message_length = 20  # We claim message is 20 bytes
      partial_message = "only 15 bytes"  # But provide only 15

      data = <<protocol_id::8, message_length::32-little, partial_message::binary>>

      # Parse the message
      result = MessageParsers.parse_up_message(data)

      # Should indicate more data is needed
      assert {:need_more, ^data} = result
    end

    test "handles too small buffer" do
      # Buffer smaller than 5 bytes (can't even read header)
      small_buffer = <<42::8, 1, 2, 3>>  # Only 4 bytes

      # Parse the message
      result = MessageParsers.parse_up_message(small_buffer)

      # Should indicate more data is needed
      assert {:need_more, ^small_buffer} = result
    end
  end
end
