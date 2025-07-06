defmodule Jamixir.Fuzzer.Util do
  @message_types %{
    0 => :peer_info,
    1 => :import_block,
    2 => :set_state,
    3 => :get_state,
    4 => :state,
    5 => :state_root
  }

  @to_message_types %{
    :peer_info => 0,
    :import_block => 1,
    :set_state => 2,
    :get_state => 3,
    :state => 4,
    :state_root => 5
  }

  def message_type_to_atom(message_type) do
    @message_types[message_type]
  end

  def atom_to_message_type(atom) do
    @to_message_types[atom]
  end

  defp parse_message(:peer_info, message) do
    try do
      versions_bytes = 6
      message_length = byte_size(message)

      if message_length < versions_bytes do
        {:error, :message_too_short}
      else
        name_length = message_length - versions_bytes

        <<name::binary-size(name_length), version_major::8, version_minor::8,
          version_patch::8, protocol_major::8, protocol_minor::8, protocol_patch::8>> = message

        {:ok, :peer_info,
         {name, {version_major, version_minor, version_patch},
          {protocol_major, protocol_minor, protocol_patch}}}
      end
    rescue
      MatchError -> {:error, :invalid_peer_info_format}
    end
  end

  defp parse_message(_type, _message) do
    # TODO: Implement
  end

  def encode_message(message_type, message) do
    full_msg = <<atom_to_message_type(message_type)::8, message::binary>>
    <<byte_size(full_msg)::32-little, full_msg::binary>>
  end

  def decode(data) when is_binary(data) do
    try do
      <<length::32-little, protocol::8, message::binary-size(length - 1)>> = data
      message_type = message_type_to_atom(protocol)

      case message_type do
        nil -> {:error, :unknown_protocol}
        type -> parse_message(type, message)
      end
    rescue
      MatchError -> {:error, :invalid_format}
    end
  end
end
