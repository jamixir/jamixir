defmodule Jamixir.RPC.HandlerTest do
  alias Jamixir.Genesis
  alias Jamixir.NodeStateServer
  use ExUnit.Case, async: false
  import Jamixir.Factory
  import Codec.Encoder

  setup do
    s = build(:genesis_state)
    Storage.put(Genesis.genesis_block_header(), s)

    header = build(:decodable_header, timeslot: 42)
    Storage.put(header)
    {:ok, state: s}
  end

  describe "handle_request/2" do
    test "handles parameters method" do
      request = %{"jsonrpc" => "2.0", "method" => "parameters", "id" => 1}

      response = Jamixir.RPC.Handler.handle_request(request)

      assert response.jsonrpc == "2.0"
      assert response.id == 1
      assert is_map(response.result)
      assert response.result["V1"]["val_count"] == 6
    end

    test "handles bestBlock method" do
      request = %{"jsonrpc" => "2.0", "method" => "bestBlock", "id" => 2}

      response = Jamixir.RPC.Handler.handle_request(request)

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
      request = %{"jsonrpc" => "2.0", "method" => "finalizedBlock", "id" => 3}

      response = Jamixir.RPC.Handler.handle_request(request)

      assert response.jsonrpc == "2.0"
      assert response.id == 3
      assert is_list(response.result)
    end

    test "handles statistics method", %{state: state} do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "statistics",
        "params" => [
          Genesis.genesis_header_hash() |> :binary.bin_to_list()
        ]
      }

      response = Jamixir.RPC.Handler.handle_request(request)

      assert response.jsonrpc == "2.0"
      assert is_list(response.result)

      blob = response.result |> :binary.list_to_bin()
      assert e(state.validator_statistics) == blob
    end

    test "handles unknown method" do
      request = %{"jsonrpc" => "2.0", "method" => "unknownMethod", "id" => 4}

      response = Jamixir.RPC.Handler.handle_request(request)

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
end
