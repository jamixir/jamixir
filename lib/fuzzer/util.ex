defmodule Jamixir.Fuzzer.Util do
  alias Block.Header
  alias Codec.State.Trie
  alias Codec.State.Trie.SerializedState
  alias Util.Logger
  import Util.Hex, only: [b16: 1]

  @protocol_to_message_type %{
    0 => :peer_info,
    1 => :import_block,
    2 => :initialize,
    3 => :get_state,
    4 => :state,
    5 => :state_root,
    255 => :error
  }

  @message_type_to_protocol %{
    :peer_info => 0,
    :import_block => 1,
    :initialize => 2,
    :get_state => 3,
    :state => 4,
    :state_root => 5,
    :error => 255
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
      <<>> ->
        {:error, :empty_raw_message}

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
    case receive_exact_bytes(socket, 4, timeout) do
      {:ok, length_bytes} ->
        <<length::32-little>> = length_bytes

        case receive_exact_bytes(socket, length, timeout) do
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

  defp receive_exact_bytes(socket, bytes_needed, timeout) do
    short_timeout = min(timeout, 10_000)

    case :socket.recv(socket, bytes_needed, short_timeout) do
      {:ok, data} when byte_size(data) == bytes_needed ->
        {:ok, data}

      {:ok, data} when byte_size(data) < bytes_needed ->
        {:error, {:incomplete_message, byte_size(data), bytes_needed, b16(data)}}

      {:error, :timeout} ->
        {:error, {:timeout_waiting, 0, bytes_needed}}

      {:error, {:timeout, partial_data}} ->
        {:error,
         {:timeout_with_partial, byte_size(partial_data), bytes_needed, b16(partial_data)}}

      error ->
        error
    end
  end

  defp parse(:peer_info, bin) do
    <<fuzz_version::8, fuzz_features::32, bin::binary>> = bin
    <<jam_version_maj::8, jam_version_min::8, jam_version_patch::8, bin::binary>> = bin
    <<app_version_maj::8, app_version_min::8, app_version_patch::8, bin::binary>> = bin
    <<name_length::8, name::binary-size(name_length)>> = bin

    parsed_data = %{
      name: name,
      jam_version: {jam_version_maj, jam_version_min, jam_version_patch},
      app_version: {app_version_maj, app_version_min, app_version_patch},
      fuzz_version: fuzz_version,
      fuzz_features: fuzz_features
    }

    {:ok, :peer_info, parsed_data}
  rescue
    e ->
      Logger.error(inspect(e))
      {:error, :invalid_peer_info_format}
  end

  defp parse(:get_state, bin) do
    {:ok, :get_state, %{header_hash: bin}}
  end

  defp parse(:initialize, bin) do
    if byte_size(bin) < 32 do
      {:error, {:message_too_short, :initialize, byte_size(bin), 32}}
    else
      try do
        {header, state_bin} = Header.decode(bin)

        if byte_size(state_bin) == 0 do
          {:error, {:empty_state_data, :initialize}}
        else
          case Trie.from_binary(state_bin) do
            {:ok, serialized_state, _} ->
              state = Trie.trie_to_state(serialized_state)
              {:ok, :initialize, %{header: header, state: state}}

            {:error, reason} ->
              {:error, reason}
          end
        end
      rescue
        MatchError -> {:error, :invalid_set_state_format}
      end
    end
  end

  defp parse(:state, bin) do
    case Trie.from_binary(bin) do
      {:ok, %SerializedState{data: state_map}, _} ->
        state = Trie.trie_to_state(state_map)
        {:ok, :state, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(:state_root, bin) do
    {:ok, :state_root, bin}
  end

  defp parse(:error, bin) do
    {:ok, :error, bin}
  end

  defp parse(:import_block, bin) do
    {block, _rest} = Block.decode(bin)
    {:ok, :import_block, block}
  rescue
    e ->
      Logger.error(inspect(e))
      {:error, :invalid_import_block_format}
  end

  defp parse(message_type, bin) do
    # For unimplemented message types, return the raw data
    {:ok, message_type, %{raw_data: bin}}
  end
end
