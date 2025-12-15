defmodule Network.MessageParsers do
  import Codec.Encoder

  @log_context "PARSE_MESSAGES"
  use Util.Logger

  def parse_ce_messages(data) do
    parse_ce_messages(data, [])
  end

  defp parse_ce_messages(<<>>, acc) do
    debug("Empty binary, returning accumulated messages: #{length(acc)}")
    Enum.reverse(acc)
  end

  defp parse_ce_messages(buffer, acc) do
    log(
      :debug,
      "Processing buffer of size #{byte_size(buffer)}, current messages: #{length(acc)}"
    )

    case buffer do
      <<length::32-little, rest::binary>> ->
        log(
          :debug,
          "Message length: #{length}, remaining buffer size: #{byte_size(rest)}"
        )

        case rest do
          <<message::binary-size(length), remaining::binary>> ->
            log(
              :debug,
              "Extracted message of size #{byte_size(message)}, remaining buffer size: #{byte_size(remaining)}"
            )

            message_preview =
              if byte_size(message) > 0, do: inspect(binary_slice(message, 0, 16)), else: "empty"

            debug("Message preview: #{message_preview}")

            parse_ce_messages(remaining, [message | acc])

          _ ->
            log(
              :error,
              "Buffer incomplete. Length header: #{length}, but only #{byte_size(rest)} bytes available"
            )

            # Not enough data for a complete message - shouldn't happen with FIN flag
            debug("Returning accumulated messages: #{length(acc)}")
            Enum.reverse(acc)
        end

      malformed ->
        log(
          :error,
          "Malformed buffer without proper length header. Size: #{byte_size(malformed)}, Preview: #{inspect(binary_part(malformed, 0, min(16, byte_size(malformed))))}"
        )

        Enum.reverse(acc)
    end
  end

  def parse_protocol_specific_messages(137, [first, second, third]) do
    [first, parse_shards(second), parse_justification(third)]
  end

  def parse_protocol_specific_messages(138, [first, second]) do
    [first, parse_justification(second)]
  end

  def parse_protocol_specific_messages(129, [bounderies_bin, trie_bin]) do
    bounderies =
      for <<b::binary-size(512) <- bounderies_bin>> do
        b
      end

    [bounderies, trie_bin]
  end

  # Default implementation for all other protocol IDs
  def parse_protocol_specific_messages(_protocol_id, messages), do: messages

  defp parse_shards(binary) do
    for <<shard::b(segment_shard) <- binary>> do
      shard
    end
  end

  defp parse_justification(binary) do
    Stream.unfold(binary, fn
      <<0, h::b(hash), rest::binary>> -> {<<0>> <> h, rest}
      <<1, h1::b(hash), h2::b(hash), rest::binary>> -> {<<1>> <> h1 <> h2, rest}
      <<>> -> nil
    end)
    |> Enum.to_list()
  end

  def parse_up_protocol_id(buffer) do
    log_tag = "PARSE_UP_PROTOCOL_ID"

    if byte_size(buffer) < 1 do
      debug("#{log_tag}: Buffer too small for protocol ID")
      {:need_more, buffer}
    else
      <<protocol_id::8, rest::binary>> = buffer
      debug("#{log_tag}: Protocol ID #{protocol_id} extracted")
      {:protocol, protocol_id, rest}
    end
  end

  def parse_up_message(buffer) do
    log_tag = "PARSE_UP_MESSAGE"

    if byte_size(buffer) < 4 do
      debug("#{log_tag}: Buffer too small for message length")
      {:need_more, buffer}
    else
      <<length::32-little, rest::binary>> = buffer

      if byte_size(rest) >= length do
        <<message::binary-size(length), remaining::binary>> = rest
        debug("#{log_tag}: Parsed complete message of size #{length}")
        {:complete, message, remaining}
      else
        log(
          :debug,
          "#{log_tag}: Incomplete message, needed #{length}, have #{byte_size(rest)}"
        )

        {:need_more, buffer}
      end
    end
  end
end
