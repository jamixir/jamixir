defmodule Jamixir.RPC.IntegrationTest do
  use ExUnit.Case, async: false
  import Jamixir.Factory
  import Codec.Encoder

  @rpc_port 19801

  setup do
    header = build(:decodable_header, timeslot: 123)
    Storage.put(header)

    {:ok, header: header}
  end

  # @moduletag :skip
  describe "HTTP RPC" do
    test "parameters endpoint works" do
      request = %{"jsonrpc" => "2.0", "method" => "parameters"}

      response = http_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["result"]["val_count"] == Constants.validator_count()
    end

    test "bestBlock endpoint works", %{header: header} do
      request = %{"jsonrpc" => "2.0", "method" => "bestBlock"}

      response = http_request(request)

      assert response["jsonrpc"] == "2.0"

      [hash_array, timeslot] = response["result"]
      assert is_list(hash_array)
      assert hash_array |> :binary.list_to_bin() == h(e(header))
      assert timeslot == 123
    end

    test "finalizedBlock endpoint works", %{header: header} do
      request = %{"jsonrpc" => "2.0", "method" => "finalizedBlock"}

      response = http_request(request)

      assert response["jsonrpc"] == "2.0"

      [hash_array, timeslot] = response["result"]
      assert is_list(hash_array)
      assert hash_array |> :binary.list_to_bin() == h(e(header))
      assert timeslot == 123
    end

    test "unknown method returns error" do
      request = %{"jsonrpc" => "2.0", "method" => "unknownMethod"}

      response = http_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["error"]["code"] == -32601
    end
  end

  defp http_request(body) do
    url = ~c"http://localhost:#{@rpc_port}/rpc"
    headers = [{~c"content-type", ~c"application/json"}]
    json_body = Jason.encode!(body)

    case :httpc.request(:post, {url, headers, ~c"application/json", json_body}, [], []) do
      {:ok, {{_version, 200, _reason_phrase}, _headers, response_body}} ->
        Jason.decode!(response_body)

      {:ok, {{_version, status, reason_phrase}, _headers, response_body}} ->
        flunk("HTTP #{status} #{reason_phrase}: #{response_body}")

      {:error, reason} ->
        flunk(
          "Connection error: #{inspect(reason)}. Make sure the RPC server is running on port #{@rpc_port}"
        )
    end
  end
end
