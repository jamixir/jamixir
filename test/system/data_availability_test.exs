defmodule System.DataAvailabilityTest do
  alias Network.ConnectionManager
  alias Jamixir.NodeCLIServer
  alias Network.Connection
  alias Util.Hash
  import Codec.Encoder
  import System.DataAvailability
  import Jamixir.Factory
  import Mox
  use ExUnit.Case, async: false

  setup :verify_on_exit!

  describe "do_get_segment/2" do
    setup do
      Application.delete_env(:jamixir, :data_availability)
      Application.put_env(:jamixir, :node_cli_server, NodeCLIServerMock)

      root = Hash.random()

      Storage.set_segment_core(root, 1)

      on_exit(fn ->
        Application.put_env(:jamixir, :data_availability, DAMock)
        Application.delete_env(:jamixir, :node_cli_server)
      end)

      {:ok, root: root}
    end

    test "returns binary data when found in storage" do
      root = Hash.random()
      value = <<9::m(export_segment)>>
      Storage.put_segment(root, 5, value)

      assert get_segment(root, 5) == value
    end

    test "request segments from nodes when not found in storage", %{root: root} do
      segment_index = 3

      # Mock validator connections and shard assignment
      p = spawn(fn -> :ok end)

      NodeCLIServerMock
      |> expect(:validator_connections, fn -> %{} end)

      # |> expect(:assigned_shard_index, fn _, _ -> 1 end)

      assert get_segment(root, segment_index) == []

      # Clean up
    end
  end
end
