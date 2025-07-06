defmodule Jamixir.FuzzerTest do
  use ExUnit.Case
  alias Jamixir.Test.FuzzerClient
  alias Jamixir.Meta

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
      assert data == {Meta.name(), Meta.app_version(), Meta.jam_version()}
    end
  end
end
