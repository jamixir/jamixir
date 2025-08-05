defmodule Jamixir.Fuzzer.Service do
  require Logger
  alias Codec.State.Trie
  alias System.State
  alias Jamixir.Meta
  import Util.Hex, only: [b16: 1]
  import Jamixir.Fuzzer.Util
  require Logger, as: Log

  def accept(socket_path, timeout \\ 600_000) do
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
        Log.debug("New fuzzer connected")
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


      {:error, {:recv_message_failed, reason}} ->
        case reason do
          {:timeout, partial_data} when is_binary(partial_data) ->
            Log.debug("Message timeout with #{byte_size(partial_data)} bytes partial data")
          {:timeout_with_partial, received, expected, hex_data} ->
            Log.debug("Message timeout: #{received}/#{expected} bytes (#{hex_data})")
          other ->
            Log.warning("Failed to read message data: #{inspect(other)}")
        end
        handle_client(sock, timeout)


      {:error, {:unknown_protocol, protocol_number}} ->
        Log.warning("Unknown protocol number: #{protocol_number} - ignoring message")
        handle_client(sock, timeout)

      {:error, {:message_too_short, message_type, received, expected}} ->
        Log.warning("Message too short for #{message_type}: received #{received} bytes, expected at least #{expected} bytes - ignoring message")
        handle_client(sock, timeout)

      {:error, {:empty_state_data, message_type}} ->
        Log.warning("Empty state data in #{message_type} message - ignoring message")
        handle_client(sock, timeout)

      {:error, {:empty_message_data, message_type}} ->
        Log.warning("Empty message data for #{message_type} - ignoring message")
        handle_client(sock, timeout)



      {:error, {error_atom, received, expected}} ->
        Log.debug("#{error_atom}: #{received}/#{expected} bytes - continuing")
        handle_client(sock, timeout)

      {:error, {error_atom, received, expected, hex_data}} ->
        Log.debug("#{error_atom}: #{received}/#{expected} bytes (#{hex_data}) - continuing")
        handle_client(sock, timeout)

      {:error, {error_atom, reason}} ->
          Log.warning("#{error_atom}: #{inspect(reason)}")
          handle_client(sock, timeout)


      {:error, reason} ->
        Log.error(" #{inspect(reason)} - ignoring message")
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
    case validate_state(state) do
      :ok ->
        state_root = Storage.put(header_hash, state)
        Log.info("State successfully stored for header hash: #{b16(header_hash)}")
        :socket.send(sock, encode_message(:state_root, state_root))

      {:error, reason} ->
        Log.error("Invalid state received for header hash #{b16(header_hash)}: #{reason}")
        :socket.close(sock)
    end
  end

  defp handle_message(:get_state, %{header_hash: header_hash}, sock) do
    case Storage.get_state(header_hash) do
      nil ->
        Log.info("State not found for header hash: #{b16(header_hash)}")
        :socket.send(sock, encode_message(:state, <<>>))

      state ->
        :socket.send(sock, encode_message(:state, Trie.to_binary(state)))
    end
  end

  defp handle_message(:import_block, block, sock) do
    case Jamixir.Node.add_block(block) do
      {:ok, _new_app_state, state_root} ->
        :socket.send(sock, encode_message(:state_root, state_root))

      {:error, reason} ->
        Log.info("Block import failed: #{reason}")
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

  defp validate_state(%State{} = state) do
    required_fields = [
      :authorizer_pool,
      :authorizer_queue,
      :recent_history,
      :safrole,
      :judgements,
      :entropy_pool,
      :next_validators,
      :curr_validators,
      :prev_validators,
      :core_reports,
      :timeslot,
      :privileged_services,
      :validator_statistics,
      :ready_to_accumulate,
      :accumulation_history,
      :services
    ]

    case Enum.find(required_fields, &(Map.get(state, &1) == nil)) do
      nil -> :ok
      field -> {:error, "missing or nil field: #{field}"}
    end
  end

  defp validate_state(_), do: {:error, "not a valid State struct"}
end
