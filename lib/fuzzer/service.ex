defmodule Jamixir.Fuzzer.Service do
  require Logger
  alias Codec.State.Trie
  alias Util.Logger, as: Log
  alias Jamixir.Meta
  import Util.Hex, only: [b16: 1]
  import Jamixir.Fuzzer.Util

  def accept(socket_path, timeout \\ 7_000) do
    if File.exists?(socket_path), do: File.rm!(socket_path)

    {:ok, sock} =
      :socket.open(:local, :stream, :default)

    :ok = :socket.bind(sock, %{family: :local, path: socket_path})
    :ok = :socket.listen(sock)

    Log.info("Ready to be fuzzed on #{socket_path}")
    loop_acceptor(sock, timeout)
  end

  defp loop_acceptor(listener, timeout) do
    case :socket.accept(listener, timeout) do
      {:ok, client} ->
        Log.info("New fuzzer  connected")
        Task.start(fn -> handle_client(client, timeout) end)
        loop_acceptor(listener, timeout)

      {:error, reason} ->
        Log.error("Accept error: #{inspect(reason)}")
    end
  end

  defp handle_client(sock, timeout) do
    case receive_and_parse_message(sock, timeout) do
      {:ok, message_type, parsed_data} ->
        handle_message(message_type, parsed_data, sock)
        handle_client(sock, timeout)

      {:error, :closed} ->
        Log.info("Client disconnected")
        :ok

      {:error, reason} ->
        Log.error("Message handling error: #{inspect(reason)}")
        handle_client(sock, timeout)
    end
  end

  defp handle_message(:peer_info, %{name: name, version: version, protocol: protocol}, sock) do
    {version_major, version_minor, version_patch} = version
    {protocol_major, protocol_minor, protocol_patch} = protocol

    Log.info(
      "Peer info: name=#{name}, version=#{version_major}.#{version_minor}.#{version_patch}, protocol=#{protocol_major}.#{protocol_minor}.#{protocol_patch}"
    )

    send_peer_info(sock)
  end

  defp handle_message(:set_state, %{header_hash: header_hash, state: state}, sock) do
    state_root = Storage.put(header_hash, state)

    Log.info("State successfully stored for header hash: #{b16(header_hash)}")
    :socket.send(sock, encode_message(:state_root, state_root))
  end

  defp handle_message(:get_state, %{header_hash: header_hash}, sock) do
    case Storage.get_state(header_hash) do
      nil ->
        Log.error("State not found for header hash: #{b16(header_hash)}")
        :socket.close(sock)

      state ->
        :socket.send(sock, encode_message(:state, Trie.to_binary(state)))
    end
  end

  defp handle_message(:import_block, block, sock) do
    case Jamixir.Node.add_block(block) do
      {:ok, _new_app_state, state_root} ->
        :socket.send(sock, encode_message(:state_root, state_root))

      {:error, reason} ->
        Log.error("Failed to import block: #{reason}")
        :socket.close(sock)
    end
  end

  defp handle_message(message_type, parsed_data, _sock) do
    Log.debug("Unhandled message type: #{message_type}, data: #{inspect(parsed_data)}")
  end

  defp send_peer_info(sock) do
    {app_version_major, app_version_minor, app_version_patch} = Meta.app_version()
    {jam_version_major, jam_version_minor, jam_version_patch} = Meta.jam_version()

    Log.info(
      "Sending peer info: #{Meta.name()}, #{app_version_major}.#{app_version_minor}.#{app_version_patch}, #{jam_version_major}.#{jam_version_minor}.#{jam_version_patch}"
    )

    our_info =
      <<Meta.name()::binary, app_version_major::8, app_version_minor::8, app_version_patch::8,
        jam_version_major::8, jam_version_minor::8, jam_version_patch::8>>

    :socket.send(sock, encode_message(:peer_info, our_info))
  end
end
