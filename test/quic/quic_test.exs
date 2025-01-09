defmodule QuicTest do
  @moduledoc """
  Basic test module for demonstrating QUIC server and client usage.
  Run each function in sequence to test different aspects of the QUIC implementation.
  """

  require Logger
  alias Quic.{Client}
  use ExUnit.Case

  @port 9999
  @server_name :quic_server_test
  @client_name :quic_client_test

  setup do
    Logger.info("[QUIC_TEST] Starting QUIC test")
    {_server_pid, client_pid} = QuicTestHelper.start_quic_processes(@port, @server_name, @client_name)
    {:ok, client: client_pid}
  end

  test "parallel streams", %{client: client} do
    tasks = for i <- 1..100 do
      Task.async(fn ->
        message = "Hello, server#{i}!"
        {:ok, response} = Client.send(client, 127, message)
        Logger.info("[QUIC_TEST] Response #{i}: #{inspect(response)}")
        assert response == message
        i
      end)
    end

    results = Task.await_many(tasks, 5000)
    assert length(results) == 100
  end
end
