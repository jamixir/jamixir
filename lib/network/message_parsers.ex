defmodule Network.MessageParsers do
  require Logger
  import Codec.Encoder
  use Codec.Encoder
  def log(level, message), do: Logger.log(level, " #{message}")
  def log(message), do: Logger.log(:info, " #{message}")

  def parse_ce_messages(data) do
    parse_ce_messages(data, [])
  end

  defp parse_ce_messages(<<>>, acc) do
    log(:debug, "PARSE_MESSAGES: Empty binary, returning accumulated messages: #{length(acc)}")
    Enum.reverse(acc)
  end

  defp parse_ce_messages(buffer, acc) do
    log(
      :debug,
      "PARSE_MESSAGES: Processing buffer of size #{byte_size(buffer)}, current messages: #{length(acc)}"
    )

    case buffer do
      <<length::32-little, rest::binary>> ->
        log(
          :debug,
          "PARSE_MESSAGES: Message length: #{length}, remaining buffer size: #{byte_size(rest)}"
        )

        case rest do
          <<message::binary-size(length), remaining::binary>> ->
            log(
              :debug,
              "PARSE_MESSAGES: Extracted message of size #{byte_size(message)}, remaining buffer size: #{byte_size(remaining)}"
            )

            message_preview =
              if byte_size(message) > 0 do
                inspect(binary_part(message, 0, min(16, byte_size(message))))
              else
                "empty"
              end

            log(:debug, "PARSE_MESSAGES: Message preview: #{message_preview}")

            parse_ce_messages(remaining, [message | acc])

          _ ->
            log(
              :error,
              "PARSE_MESSAGES: Buffer incomplete. Length header: #{length}, but only #{byte_size(rest)} bytes available"
            )

            # Not enough data for a complete message - shouldn't happen with FIN flag
            log(:debug, "PARSE_MESSAGES: Returning accumulated messages: #{length(acc)}")
            Enum.reverse(acc)
        end

      malformed ->
        log(
          :error,
          "PARSE_MESSAGES: Malformed buffer without proper length header. Size: #{byte_size(malformed)}, Preview: #{inspect(binary_part(malformed, 0, min(16, byte_size(malformed))))}"
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
    chunk_size = binary_registry().segment_bytes

    for <<shard::binary-size(chunk_size) <- binary>> do
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

    cond do
      byte_size(buffer) < 1 ->
        log(:debug, "#{log_tag}: Buffer too small for protocol ID")
        {:need_more, buffer}

      true ->
        <<protocol_id::8, rest::binary>> = buffer
        log(:debug, "#{log_tag}: Protocol ID #{protocol_id} extracted")
        {:protocol, protocol_id, rest}
    end
  end

  def parse_up_message(buffer) do
    log_tag = "PARSE_UP_MESSAGE"

    cond do
      byte_size(buffer) < 4 ->
        log(:debug, "#{log_tag}: Buffer too small for message length")
        {:need_more, buffer}

      true ->
        <<length::32-little, rest::binary>> = buffer

        if byte_size(rest) >= length do
          <<message::binary-size(length), remaining::binary>> = rest
          log(:debug, "#{log_tag}: Parsed complete message of size #{length}")
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
