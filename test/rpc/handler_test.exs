defmodule Jamixir.RPC.HandlerTest do
  alias Codec.State.Trie
  alias Block.Extrinsic
  alias Jamixir.Genesis
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.Encoder
  import Util.Hex
  import Mox

  setup do
    services = %{1 => build(:service_account), 7 => build(:service_account)}
    s = %{build(:genesis_state) | services: services}
    s = %{s | recent_history: build(:recent_history)}
    Storage.put(Genesis.genesis_header_hash(), s)

    header = build(:decodable_header, timeslot: 42)
    Storage.put(header)
    {:ok, state: s}
  end

  describe "handle_request/2" do
    setup do
      Application.put_env(:jamixir, NodeAPI, Jamixir.Node)

      on_exit(fn ->
        Application.put_env(:jamixir, NodeAPI, Jamixir.NodeAPI.Mock)
      end)
    end

    test "handles parameters method" do
      request = %{"method" => "parameters", "id" => 1}

      response = response(request)

      assert response.jsonrpc == "2.0"
      assert response.id == 1
      assert is_map(response.result)
      assert response.result["V1"]["val_count"] == 6
    end

    test "handles bestBlock method" do
      request = %{"method" => "bestBlock", "id" => 2}

      response = response(request)

      assert response.jsonrpc == "2.0"
      assert response.id == 2
      assert is_list(response.result)
      assert length(response.result) == 2

      [hash, timeslot] = response.result
      # Hash should be 32 bytes
      assert byte_size(d64(hash)) == 32
      assert timeslot == 42
    end

    test "handles finalizedBlock method" do
      request = %{"method" => "finalizedBlock", "id" => 3}
      response = response(request)

      assert response.jsonrpc == "2.0"
      assert response.id == 3
      assert is_list(response.result)
    end

    test "handles statistics method", %{state: state} do
      request = %{"method" => "statistics", "params" => [gen_head()]}

      response = response(request)

      assert response.jsonrpc == "2.0"
      blob = d64(response.result)
      assert e(state.validator_statistics) == blob
    end

    test "handles listServices method" do
      response = response(%{"method" => "listServices", "params" => [gen_head()]})
      assert response.result == [1, 7]
    end

    test "handles serviceData method", %{state: state} do
      request = %{"method" => "serviceData", "params" => [gen_head(), 7]}
      response = response(request)
      assert d64(response.result) == e(state.services[7])
    end

    test "handles serviceData method when service doesn't exist" do
      request = %{"method" => "serviceData", "params" => [gen_head(), 8]}
      response = response(request)
      assert d64(response.result) == <<>>
    end

    test "handles serviceValue method", %{state: state} do
      [_, hash] = state.services[7].storage.original_map |> Map.keys()
      params = [gen_head(), 7, e64(hash)]
      request = %{"method" => "serviceValue", "params" => params}

      assert d64(response(request).result) == state.services[7].storage[hash]
    end

    test "handles servicePreimage method", %{state: state} do
      [{hash, value}] = Map.to_list(state.services[7].preimage_storage_p)
      params = [gen_head(), 7, e64(hash)]
      request = %{"method" => "servicePreimage", "params" => params}

      assert d64(response(request).result) == value
    end

    test "handles servicePreimage method when preimage is null" do
      hash = e64(Util.Hash.one())
      request = %{"method" => "servicePreimage", "params" => [gen_head(), 7, hash]}
      assert response(request).result == nil
    end

    test "handles serviceRequest method", %{state: state} do
      [{hash, length}, _] = state.services[7].storage.original_map |> Map.keys()
      params = [gen_head(), 7, e64(hash), length]
      request = %{"method" => "serviceRequest", "params" => params}

      assert response(request).result == state.services[7].storage[{hash, length}]
    end

    test "handles serviceRequest method, invalid key" do
      params = [gen_head(), 7, e64(Util.Hash.one()), 7]
      request = %{"method" => "serviceRequest", "params" => params}

      assert response(request).result == nil
    end

    test "handles beefyRoot method", %{state: state} do
      # make genesis the last block
      Storage.put(Genesis.genesis_block_header(), state)

      %{recent_history: %{blocks: [_, b2]}} = state
      hash = e64(b2.header_hash)
      request = %{"method" => "beefyRoot", "params" => [hash]}
      response = response(request)
      assert response.result == e64(b2.beefy_root)
    end

    test "handles submitPreimage method" do
      Application.put_env(:jamixir, NodeAPI, Jamixir.NodeAPI.Mock)

      request = %{"method" => "submitPreimage", "params" => [7, e64(<<1, 2, 3, 4>>), gen_head()]}
      Jamixir.NodeAPI.Mock |> expect(:save_preimage, 1, fn <<1, 2, 3, 4>> -> :ok end)
      response = response(request)
      assert response.result == []
      verify!()
    end

    test "handles submitWorkPackage method" do
      Application.put_env(:jamixir, NodeAPI, Jamixir.NodeAPI.Mock)
      {work_package, extrinsics} = work_package_and_its_extrinsic_factory()
      core = 3
      extrinsics = List.flatten(extrinsics)

      Jamixir.NodeAPI.Mock
      |> expect(:save_work_package, fn ^work_package, ^core, ^extrinsics -> :ok end)

      wp_bin = e64(e(work_package))
      ex_bins = for e <- extrinsics, do: e64(e)
      request = %{"method" => "submitWorkPackage", "params" => [core, wp_bin, ex_bins]}
      response = response(request)
      assert response.result == []

      verify!()
    end

    test "handles parent method with parent" do
      block1 =
        build(:decodable_block,
          parent_hash: Genesis.genesis_header_hash(),
          extrinsic: %Extrinsic{}
        )

      hash1 = h(e(block1.header))
      block2 = build(:decodable_block, parent_hash: hash1, extrinsic: %Extrinsic{})

      Storage.put(block1)
      Storage.put(block2)

      hash2 = e64(h(e(block2.header)))

      response = response(%{"method" => "parent", "params" => [hash2]})

      [hash, timeslot] = response.result
      assert hash == e64(hash1)
      assert timeslot == block1.header.timeslot
    end

    test "handles parent method parent is nil" do
      response = response(%{"method" => "parent", "params" => [gen_head()]})
      assert response.result == nil
    end

    test "handles stateRoot method", %{state: state} do
      request = %{"method" => "stateRoot", "params" => [gen_head()]}
      assert response(request).result == e64(Trie.state_root(state))
    end

    test "handles stateRoot method invalid header hash" do
      hash = e64(Util.Hash.one())
      request = %{"method" => "stateRoot", "params" => [hash]}
      assert response(request).result == nil
    end

    test "handles syncState method" do
      request = %{"method" => "syncState", "params" => []}
      %{"num_peers" => _, "status" => "Completed"} = response(request).result
    end

    test "handles unknown method" do
      response = response(%{"method" => "unknownMethod", "id" => 4})
      assert response.jsonrpc == "2.0"
      assert response.id == 4
      assert response.error.code == -32601
      assert response.error.message =~ "Method not found"
    end

    test "handles invalid request" do
      request = %{"invalid" => "request"}

      response = Jamixir.RPC.Handler.handle_request(request)

      assert response.jsonrpc == "2.0"
      assert response.error.code == -32600
      assert response.error.message == "Invalid Request"
    end

    test "handles batch requests" do
      requests = [
        %{"jsonrpc" => "2.0", "method" => "parameters", "id" => 1},
        %{"jsonrpc" => "2.0", "method" => "bestBlock", "id" => 2}
      ]

      responses = Jamixir.RPC.Handler.handle_request(requests)

      assert is_list(responses)
      assert length(responses) == 2

      Enum.each(responses, fn response ->
        assert response.jsonrpc == "2.0"
        assert is_integer(response.id)
      end)
    end
  end

  def gen_head, do: e64(Genesis.genesis_header_hash())

  def response(request) do
    Jamixir.RPC.Handler.handle_request(put_in(request, ["jsonrpc"], "2.0"))
  end
end
