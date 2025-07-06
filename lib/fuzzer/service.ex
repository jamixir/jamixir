defmodule Jamixir.Fuzzer do
  require Logger
  alias Util.Logger, as: Log
  alias Jamixir.Meta
  import Jamixir.Fuzzer.Util

  def accept(socket_path) do
    if File.exists?(socket_path), do: File.rm!(socket_path)

    {:ok, sock} =
      :socket.open(:local, :stream, :default)

    :ok = :socket.bind(sock, %{family: :local, path: socket_path})
    :ok = :socket.listen(sock)

    Log.info("Ready to be fuzzed on #{socket_path}")
    loop_acceptor(sock)
  end

  defp loop_acceptor(listener) do
    case :socket.accept(listener) do
      {:ok, client} ->
        Log.info("New fuzzer  connected")
        Task.start(fn -> handle_client(client) end)
        loop_acceptor(listener)

      {:error, reason} ->
        Log.error("Accept error: #{inspect(reason)}")
    end
  end

  defp handle_client(sock) do
    case :socket.recv(sock, 0) do
      {:ok, data} ->
        case decode(data) do
          {:ok, message_type, parsed_data} ->
            handle_message(message_type, parsed_data, sock)

          {:error, reason} ->
            Log.error("Decode error: #{inspect(reason)}")
        end

        handle_client(sock)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Log.error("Recv error: #{inspect(reason)}")
    end
  end

  defp handle_message(:peer_info, parsed_data, sock) do
    {name, {version_major, version_minor, version_patch},
     {protocol_major, protocol_minor, protocol_patch}} = parsed_data

    Log.info(
      "Peer info: name=#{name}, version=#{version_major}.#{version_minor}.#{version_patch}, protocol=#{protocol_major}.#{protocol_minor}.#{protocol_patch}"
    )

    send_peer_info(sock)
  end

  defp handle_message(:import_block, _parsed_data, _sock) do
    # TODO: Implement
  end

  defp handle_message(:set_state, _parsed_data, _sock) do
    # TODO: Implement
  end

  defp handle_message(:get_state, _parsed_data, _sock) do
    # TODO: Implement
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
