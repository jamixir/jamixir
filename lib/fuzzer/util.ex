defmodule Jamixir.Fuzzer.Util do
  require Logger

  @protocol_to_message_type %{
    0 => :peer_info,
    1 => :import_block,
    2 => :set_state,
    3 => :get_state,
    4 => :state,
    5 => :state_root
  }

  @message_type_to_protocol %{
    :peer_info => 0,
    :import_block => 1,
    :set_state => 2,
    :get_state => 3,
    :state => 4,
    :state_root => 5
  }

  def receive_and_parse_message(socket, timeout) do
    with {:ok, raw_data} <- receive_raw_message(socket, timeout),
         {:ok, message_type, parsed_data} <- parse_raw_message(raw_data) do
      {:ok, message_type, parsed_data}
    else
      error -> error
    end
  end

  def parse_raw_message(raw_data) do
    case raw_data do
      <<protocol_number::8, message_bin::binary>> ->
        case @protocol_to_message_type[protocol_number] do
          nil ->
            {:error, {:unknown_protocol, protocol_number}}

          message_type ->
            parse(message_type, message_bin)
        end

      _ ->
        {:error, :invalid_message_format}
    end
  end

  def encode_message(message_type, message) do
    protocol_number = @message_type_to_protocol[message_type]
    full_msg = <<protocol_number::8, message::binary>>
    <<byte_size(full_msg)::32-little, full_msg::binary>>
  end

  # Private functions

  defp receive_raw_message(socket, timeout) do
    # First read the 4-byte length field
    case :socket.recv(socket, 4, timeout) do
      {:ok, <<length::32-little>>} ->
        case :socket.recv(socket, length, timeout) do
          {:ok, message_data} ->
            {:ok, message_data}

          {:error, reason} ->
            {:error, {:recv_message_failed, reason}}
        end

      {:error, :closed} ->
        {:error, :closed}

      {:error, reason} ->
        {:error, {:recv_length_failed, reason}}
    end
  end

  defp parse(:peer_info, bin) do
    try do
      versions_bytes = 6
      message_length = byte_size(bin)

      if message_length < versions_bytes do
        {:error, :peer_info_too_short}
      else
        name_length = message_length - versions_bytes

        <<name::binary-size(name_length), version_major::8, version_minor::8, version_patch::8,
          protocol_major::8, protocol_minor::8, protocol_patch::8>> = bin

        parsed_data = %{
          name: name,
          version: {version_major, version_minor, version_patch},
          protocol: {protocol_major, protocol_minor, protocol_patch}
        }

        {:ok, :peer_info, parsed_data}
      end
    rescue
      MatchError -> {:error, :invalid_peer_info_format}
    end
  end

  defp parse(:get_state, bin) do
    {:ok, :get_state, %{header_hash: bin}}
  end

  defp parse(:state, bin) do
    # for the moment, we are not doing the fuzzer side
    # therefore not bothering with reconstructing the state from the binary
    {:ok, :state, bin}
  end

  defp parse(message_type, bin) do
    # For unimplemented message types, return the raw data
    {:ok, message_type, %{raw_data: bin}}
  end
end
