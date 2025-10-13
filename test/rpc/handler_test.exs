defmodule Jamixir.RPC.HandlerTest do
  alias Codec.State.Trie
  alias Block.Extrinsic
  alias Jamixir.Genesis
  use ExUnit.Case, async: false
  import Jamixir.Factory
  import Codec.Encoder
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

      [hash_array, timeslot] = response.result
      assert is_list(hash_array)
      # Hash should be 32 bytes
      assert length(hash_array) == 32
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
      blob = response.result |> :binary.list_to_bin()
      assert e(state.validator_statistics) == blob
    end

    test "handles listServices method" do
      response = response(%{"method" => "listServices", "params" => [gen_head()]})
      assert response.result == [1, 7]
    end

    test "handles serviceData method", %{state: state} do
      request = %{"method" => "serviceData", "params" => [gen_head(), 7]}
      response = response(request)
      assert response.result |> :binary.list_to_bin() == e(state.services[7])
    end

    test "handles serviceData method when service doesn't exist" do
      request = %{"method" => "serviceData", "params" => [gen_head(), 8]}
      response = response(request)
      assert response.result |> :binary.list_to_bin() == <<>>
    end

    test "handles serviceValue method", %{state: state} do
      [_, hash] = state.services[7].storage.original_map |> Map.keys()
      params = [gen_head(), 7, hash |> :binary.bin_to_list()]
      request = %{"method" => "serviceValue", "params" => params}

      assert response(request).result |> :binary.list_to_bin() == state.services[7].storage[hash]
    end

    test "handles servicePreimage method", %{state: state} do
      [{hash, value}] = Map.to_list(state.services[7].preimage_storage_p)
      params = [gen_head(), 7, hash |> :binary.bin_to_list()]
      request = %{"method" => "servicePreimage", "params" => params}

      assert response(request).result |> :binary.list_to_bin() == value
    end

    test "handles servicePreimage method when preimage is null" do
      hash = Util.Hash.one() |> :binary.bin_to_list()
      request = %{"method" => "servicePreimage", "params" => [gen_head(), 7, hash]}
      assert response(request).result == nil
    end

    test "handles serviceRequest method", %{state: state} do
      [{hash, length}, _] = state.services[7].storage.original_map |> Map.keys()
      params = [gen_head(), 7, hash |> :binary.bin_to_list(), length]
      request = %{"method" => "serviceRequest", "params" => params}

      assert response(request).result == state.services[7].storage[{hash, length}]
    end

    test "handles serviceRequest method, invalid key" do
      params = [gen_head(), 7, Util.Hash.one() |> :binary.bin_to_list(), 7]
      request = %{"method" => "serviceRequest", "params" => params}

      assert response(request).result == nil
    end

    test "handles beefyRoot method", %{state: state} do
      # make genesis the last block
      Storage.put(Genesis.genesis_block_header(), state)

      %{recent_history: %{blocks: [_, b2]}} = state
      hash = b2.header_hash |> :binary.bin_to_list()
      request = %{"method" => "beefyRoot", "params" => [hash]}
      response = response(request)
      assert response.result |> :binary.list_to_bin() == b2.beefy_root
    end

    test "handles submitPreimage method" do
      request = %{"method" => "submitPreimage", "params" => [7, [1, 2, 3, 4], gen_head()]}
      Jamixir.NodeAPI.Mock |> expect(:save_preimage, 1, fn <<1, 2, 3, 4>> -> :ok end)
      response = response(request)
      assert response.result == []
      verify!()
    end

    test "handles submitWorkPackage method" do
      {work_package, extrinsics} = work_package_and_its_extrinsic_factory()
      core = 3

      Jamixir.NodeAPI.Mock
      |> expect(:save_work_package, fn ^work_package, ^core, ^extrinsics -> :ok end)

      wp_bin = e(work_package) |> :binary.bin_to_list()
      ex_bins = for e <- extrinsics, do: :binary.bin_to_list(e)
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

      hash2 = h(e(block2.header)) |> :binary.bin_to_list()

      response = response(%{"method" => "parent", "params" => [hash2]})

      [hash, timeslot] = response.result
      assert hash |> :binary.list_to_bin() == hash1
      assert timeslot == block1.header.timeslot
    end

    test "handles parent method parent is nil" do
      response = response(%{"method" => "parent", "params" => [gen_head()]})
      assert response.result == nil
    end

    test "handles stateRoot method", %{state: state} do
      request = %{"method" => "stateRoot", "params" => [gen_head()]}
      assert response(request).result |> :binary.list_to_bin() == Trie.state_root(state)
    end

    test "handles stateRoot method invalid header hash" do
      hash = Util.Hash.one() |> :binary.bin_to_list()
      request = %{"method" => "stateRoot", "params" => [hash]}
      assert response(request).result == nil
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

  def gen_head, do: Genesis.genesis_header_hash() |> :binary.bin_to_list()

  def response(request) do
    Jamixir.RPC.Handler.handle_request(put_in(request, ["jsonrpc"], "2.0"))
  end
end
