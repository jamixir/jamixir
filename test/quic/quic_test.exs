defmodule QuicTest do
  @moduledoc """
  Basic test module for demonstrating QUIC server and client usage.
  Run each function in sequence to test different aspects of the QUIC implementation.
  """

  require Logger
  alias QuicServer
  alias QuicClient
  use ExUnit.Case

  test "basic connection" do
    # Start server
    {:ok, _} = QuicServer.start_link(9999)
    # Wait for server to initialize
    Process.sleep(100)

    # Start client
    {:ok, client} = QuicClient.start_link()
    # Wait for connection
    Process.sleep(100)

    assert Process.alive?(client)
  end

  test "send ce message" do
    {:ok, _server} = QuicServer.start_link(9999)
    Process.sleep(100)

    {:ok, _client} = QuicClient.start_link()
    assert {:ok, "echo: ing"} = QuicClient.send_ce("ping")
    # assert {:ok, "echo: ing2"} = QuicClient.send_ce("ping2")

  end
end
