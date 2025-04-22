defmodule Network.MessageParsers do
  require Logger

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

  def parse_up_message(buffer) do
    log_tag = "PARSE_UP_MESSAGE"

    cond do
      byte_size(buffer) < 5 ->
        log(:debug, "#{log_tag} Buffer too small: #{byte_size(buffer)} bytes")
        {:need_more, buffer}

      byte_size(buffer) >= 5 ->
        <<_protocol_id::8, message_size::32-little, rest::binary>> = buffer

        log(
          :debug,
          "#{log_tag} Message header: size=#{message_size}, rest=#{byte_size(rest)} bytes"
        )

        if byte_size(rest) >= message_size do
          <<message::binary-size(message_size), remaining::binary>> = rest
          {:complete, message, remaining}
        else
          {:need_more, buffer}
        end
    end
  end
end
