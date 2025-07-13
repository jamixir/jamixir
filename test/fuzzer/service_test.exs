defmodule Jamixir.FuzzerTest do
  use ExUnit.Case
  alias Util.Hash
  alias Jamixir.Test.FuzzerClient
  alias Jamixir.Meta
  alias Codec.State.Trie
  alias Storage
  import Jamixir.Factory
  alias Util.Hash

  @socket_path "/tmp/jamixir_fuzzer_test.sock"

  setup do
    if File.exists?(@socket_path), do: File.rm!(@socket_path)

    fuzzer_pid = Task.start_link(fn -> Jamixir.Fuzzer.accept(@socket_path) end)

    # Give it a moment to start
    Process.sleep(100)

    {:ok, client} = FuzzerClient.connect(@socket_path)

    on_exit(fn ->
      FuzzerClient.disconnect(client)
      if File.exists?(@socket_path), do: File.rm!(@socket_path)
    end)

    {:ok, client: client, fuzzer_pid: fuzzer_pid}
  end

  defp build_peer_info_message(name, app_version, jam_version) do
    {app_version_major, app_version_minor, app_version_patch} = app_version
    {jam_version_major, jam_version_minor, jam_version_patch} = jam_version

    <<name::binary, app_version_major::8, app_version_minor::8, app_version_patch::8,
      jam_version_major::8, jam_version_minor::8, jam_version_patch::8>>
  end

  describe "peer_info handler" do
    test "handles basic peer info exchange", %{client: client} do
      msg = build_peer_info_message(Meta.name(), {0, 1, 0}, {1, 0, 0})
      assert {:ok, :peer_info, data} = FuzzerClient.send_and_receive(client, :peer_info, msg)

      assert %{name: name, version: version, protocol: protocol} = data
      assert name == Meta.name()
      assert version == Meta.app_version()
      assert protocol == Meta.jam_version()
    end
  end

  describe "get_state handler" do
    test "handles get_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state

      serialized_state = Trie.serialize(state)

      expected_data =
        for {key, value} <- serialized_state.data, into: <<>> do
          <<key::binary, value::binary>>
        end

      header_hash = Hash.one()
      Storage.put(header_hash, serialized_state)

      # Request the state
      assert {:ok, :state, state_bin} =
               FuzzerClient.send_and_receive(client, :get_state, header_hash)

      assert state_bin == expected_data
    end

    test "handles get_state request for non-existent state", %{client: client} do
      # Request a state that doesn't exist
      non_existent_hash = Hash.random()

      # The service should not send a response for non-existent states
      # note, this is a guess, the protocol doesn't mention what to do in this case
      # and since the fuzzer is an intrenal test tool, this should not happen and should not really be a concern
      # We expect a timeout or error
      result = FuzzerClient.send_and_receive(client, :get_state, non_existent_hash, 1000)

      # The service logs an error but doesn't send a response for non-existent states
      # So we expect a timeout or error
      assert result == {:error, :closed}
    end
  end
end
