defmodule QuicTest do
  @moduledoc """
  Basic test module for demonstrating QUIC server and client usage.
  Run each function in sequence to test different aspects of the QUIC implementation.
  """

  require Logger
  alias QuicServer
  alias QuicClient
  use ExUnit.Case


  # test "basic connection" do
  #   # Start server
  #   {:ok, _} = QuicServer.start_link(9999)
  #   # Wait for server to initialize
  #   Process.sleep(100)

  #   # Start client
  #   {:ok, client} = QuicClient.start_link()
  #   # Wait for connection
  #   Process.sleep(100)

  #   assert Process.alive?(client)
  # end

  # test "send ce message" do
  #   {:ok, _server} = QuicServer.start_link(9999)
  #   Process.sleep(100)


  #   {:ok, _client} = QuicClient.start_link()
  #   result = QuicClient.send_ce("ping")
  #   # Process.sleep(100)  # Give time for cleanup
  #   assert result == {:ok, "echo: ping"}
  # end

  test "basic client" do
    BasicQuicServer.start_link(9999)
    Process.sleep(100)

    {:ok, client_pid} = BasicQuicClient.start_link()
    Process.sleep(100)

    {:ok, response} = BasicQuicClient.send_and_wait(client_pid, "Hello, server!")
    Process.sleep(10)
    {:ok, response2} = BasicQuicClient.send_and_wait(client_pid, "Hello, server2!")
    IO.puts("Test received response: #{inspect(response)}")
    IO.puts("Test received response2: #{inspect(response2)}")

    assert response == {:ok, "Hello, server!"}
    assert response2 == {:ok, "Hello, server2!"}
  end

end
