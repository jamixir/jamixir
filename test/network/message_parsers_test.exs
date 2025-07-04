defmodule Network.MessageParsersTest do
  use ExUnit.Case
  alias Network.MessageParsers

  import Mox

  setup :set_mox_global

  setup do
    original_server_calls = Application.get_env(:jamixir, :server_calls)
    Application.put_env(:jamixir, :server_calls, ServerCallsMock)

    on_exit(fn ->
      if original_server_calls do
        Application.put_env(:jamixir, :server_calls, original_server_calls)
      else
        Application.delete_env(:jamixir, :server_calls)
      end
      Mox.verify!()
    end)

    :ok
  end

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
        message1_length::32-little,
        message1::binary,
        message2_length::32-little,
        message2::binary,
        message3_length::32-little,
        message3::binary
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

  describe "parse_up_protocol_id/1" do
    test "extracts protocol ID cleanly" do
      buffer = <<42::8, 0, 1, 2, 3>>

      assert {:protocol, 42, <<0, 1, 2, 3>>} = MessageParsers.parse_up_protocol_id(buffer)
    end

    test "handles too small buffer for protocol ID" do
      buffer = <<>>

      assert {:need_more, ^buffer} = MessageParsers.parse_up_protocol_id(buffer)
    end
  end

  describe "parse_up_message/1" do
    test "handles complete message" do
      protocol_id = 42
      message = "test up message"
      message_length = byte_size(message)
      data = <<protocol_id::8, message_length::32-little, message::binary>>

      # Not enough to immediately parse => needs more
      assert {:need_more, ^data} = MessageParsers.parse_up_message(data)
    end

    test "handles complete message with remaining data" do
      protocol_id = 42
      message = "complete message"
      message_length = byte_size(message)
      remaining = "additional data"

      data = <<protocol_id::8, message_length::32-little, message::binary, remaining::binary>>

      # Same: parser needs more
      assert {:need_more, ^data} = MessageParsers.parse_up_message(data)
    end

    test "handles incomplete message" do
      protocol_id = 42
      message_length = 20
      partial_message = "only 15 bytes"

      data = <<protocol_id::8, message_length::32-little, partial_message::binary>>

      # Same again: needs more
      assert {:need_more, ^data} = MessageParsers.parse_up_message(data)
    end

    test "handles too small buffer" do
      small_buffer = <<42::8, 1, 2, 3>>

      # Too small, needs more
      assert {:need_more, ^small_buffer} = MessageParsers.parse_up_message(small_buffer)
    end

    test "separate protocol id and message separately" do
      protocol_id = 7
      message = "ping"
      message_data = <<byte_size(message)::32-little, message::binary>>

      # Step 1: extract protocol id
      assert {:protocol, ^protocol_id, <<>>} =
               MessageParsers.parse_up_protocol_id(<<protocol_id>>)

      # Step 2: parse message after
      assert {:complete, ^message, <<>>} = MessageParsers.parse_up_message(message_data)
    end

    test "coalesced protocol id and message together" do
      protocol_id = 9
      message = "pong"
      message_data = <<byte_size(message)::32-little, message::binary>>

      coalesced = <<protocol_id::8>> <> message_data

      # First, extract protocol ID
      assert {:protocol, ^protocol_id, rest} = MessageParsers.parse_up_protocol_id(coalesced)

      # Then, parse the message part
      assert {:complete, ^message, <<>>} = MessageParsers.parse_up_message(rest)
    end

    test "multiple messages after protocol" do
      protocol_id = 21
      m1 = "foo"
      m2 = "bar"

      messages = <<
        byte_size(m1)::32-little,
        m1::binary,
        byte_size(m2)::32-little,
        m2::binary
      >>

      assert {:protocol, ^protocol_id, _rest1} =
               MessageParsers.parse_up_protocol_id(<<protocol_id::8>>)

      # First message
      assert {:complete, ^m1, rest2} = MessageParsers.parse_up_message(messages)

      # Second message
      assert {:complete, ^m2, <<>>} = MessageParsers.parse_up_message(rest2)
    end
  end

  describe "handle_up_stream race condition simulation" do
    test "accumulates protocol byte and parses correctly once full data arrives" do
      initial_state = %{
        up_stream_data: %{
          123 => %{protocol_id: nil, buffer: <<>>}
        }
      }

      # Step 1: Partial first chunk, only the protocol ID
      stream_id = 123
      # Only protocol byte
      partial_data = <<42::8>>

      ServerCallsMock
      |> expect(:call, fn 42, "hello world" -> :ok end)

      {:noreply, state_after_partial} =
        Network.Server.handle_up_stream(
          partial_data,
          stream_id,
          initial_state,
          initial_state.up_stream_data[stream_id]
        )

      # Protocol ID should now be extracted and buffer should be empty
      assert state_after_partial.up_stream_data[stream_id].protocol_id == 42
      assert state_after_partial.up_stream_data[stream_id].buffer == <<>>

      # Step 2: Second chunk arrives, full message
      full_message = "hello world"
      message_length = byte_size(full_message)
      second_chunk = <<message_length::32-little, full_message::binary>>

      {:noreply, final_state} =
        Network.Server.handle_up_stream(
          second_chunk,
          stream_id,
          state_after_partial,
          state_after_partial.up_stream_data[stream_id]
        )

      # After processing the full message, buffer must be empty
      assert final_state.up_stream_data[stream_id].buffer == <<>>
    end
  end
end
