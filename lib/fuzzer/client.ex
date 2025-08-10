defmodule Jamixir.Fuzzer.Client do
  @moduledoc """
  This is the fuzzing side
  in reality this is not our responsibility
  but it aids in testing the fuzzer service
  """
  alias Codec.State.Trie
  import Jamixir.Fuzzer.Util
  import Codec.Encoder, only: [e: 1]

  defstruct [:socket, :socket_path]

  def connect(socket_path) do
    case :socket.open(:local, :stream, :default) do
      {:ok, sock} ->
        case :socket.connect(sock, %{family: :local, path: socket_path}) do
          :ok ->
            {:ok, %__MODULE__{socket: sock, socket_path: socket_path}}

          {:error, reason} ->
            :socket.close(sock)
            {:error, {:connect_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:socket_open_failed, reason}}
    end
  end

  def disconnect(%__MODULE__{socket: sock}) do
    :socket.close(sock)
  end

  def send_peer_info(client, name, version \\ {0, 1, 0}, protocol \\ {1, 0, 0}) do
    {version_major, version_minor, version_patch} = version
    {protocol_major, protocol_minor, protocol_patch} = protocol

    message =
      <<byte_size(name)::8, name::binary, version_major::8, version_minor::8, version_patch::8,
        protocol_major::8, protocol_minor::8, protocol_patch::8>>

    send_message(client, :peer_info, message)
  end

  def send_get_state(client, header_hash) do
    send_message(client, :get_state, header_hash)
  end

  def send_set_state(client, header, state) do
    header_bin = e(header)
    serialized_state = Trie.to_binary(state)
    message = header_bin <> serialized_state
    send_message(client, :set_state, message)
  end

  def send_import_block(client, block) do
    send_message(client, :import_block, e(block))
  end

  def send_message(client, message_type, message) do
    bin = encode_message(message_type, message)
    :socket.send(client.socket, bin)
  end

  def receive_message(client, timeout \\ 1000) do
    receive_and_parse_message(client.socket, timeout)
  end
end
