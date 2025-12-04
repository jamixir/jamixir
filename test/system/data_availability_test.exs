defmodule System.DataAvailabilityTest do
  alias Network.Types.SegmentShardsRequest
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
      Application.put_env(:jamixir, :node_state_server, NodeStateServerMock)
      Application.put_env(:jamixir, :network_client, ClientMock)

      root = Hash.random()
      core = 2

      Storage.set_segment_core(root, core)

      on_exit(fn ->
        Application.put_env(:jamixir, :data_availability, DAMock)
        Application.delete_env(:jamixir, :node_state_server)
        Application.delete_env(:jamixir, :network_client)
      end)

      {:ok, root: root, core: core}
    end

    test "returns binary data when found in storage" do
      root = Hash.random()
      value = <<9::m(export_segment)>>
      Storage.put_segment(root, 5, value)

      assert get_segment(root, 5) == value
    end

    @tag :full_vectors
    test "request segments from nodes when not found in storage", %{root: root, core: core} do
      segment = <<123_456_789_123_123_123::m(export_segment)>>
      segment_index = 3
      shards = ErasureCoding.erasure_code(segment)
      validators = build_list(6, :validator)
      fake_pid = 99

      # mock validators
      NodeStateServerMock
      |> expect(:current_connections, fn -> for v <- validators, do: {v, fake_pid} end)

      # for each validator, expects to get its share based on assigned shard index
      for {v, i} <- Enum.with_index(validators) do
        key = v.ed25519

        expect(NodeStateServerMock, :assigned_shard_index, fn ^core, ^key -> i end)

        req = [
          %SegmentShardsRequest{
            erasure_root: root,
            shard_index: i,
            segment_indexes: [segment_index]
          }
        ]

        expect(ClientMock, :request_segment_shards, fn ^fake_pid, ^req, false ->
          {:ok, Enum.at(shards, i)}
        end)
      end

      assert get_segment(root, segment_index) == segment
    end
  end
end
