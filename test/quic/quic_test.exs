defmodule QuicTest do
  @moduledoc """
  Basic test module for demonstrating QUIC server and client usage.
  Run each function in sequence to test different aspects of the QUIC implementation.
  """

  require Logger
  alias QuicServer
  alias QuicClient
  use ExUnit.Case

  setup do
    Logger.configure(
      level: :info,
      sync: false
    )

    # Add filter for QUIC client logs
    # :logger.add_primary_filter(
    #   :quic_client_filter,
    #   {&QuicLogFilter.filter/2, []}
    # )

    :ok
  end

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
    Logger.info("[QUIC_TEST] Starting QUIC test")
    BasicQuicServer.start_link(9999)
    Process.sleep(100)

    {:ok, client_pid} = BasicQuicClient.start_link()
    Process.sleep(100)

    for i <- 1..3 do
      message = "Hello, server#{i}!"
      {:ok, response} = BasicQuicClient.send_and_wait(client_pid, message)
      Logger.info("[QUIC_TEST] Response #{i}: #{inspect(response)}")
      assert response == {:ok, message}
      Process.sleep(50)
    end
  end
end
