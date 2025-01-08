defmodule QuicTest do
  @moduledoc """
  Basic test module for demonstrating QUIC server and client usage.
  Run each function in sequence to test different aspects of the QUIC implementation.
  """

  require Logger
  alias Quic.{Client, Server}
  use ExUnit.Case

  setup do
    # Logger.configure(
    #   level: :info,
    #   sync: false
    # )

    # Add filter for QUIC client logs
    # :logger.add_primary_filter(
    #   :quic_client_filter,
    #   {&QuicLogFilter.filter/2, []}
    # )

    :ok
  end

  test "basic client" do
    Logger.info("[QUIC_TEST] Starting QUIC test")
    Server.start_link(9999)
    Process.sleep(100)

    {:ok, client_pid} = Client.start_link()
    Process.sleep(100)

    for i <- 1..3 do
      message = "Hello, server#{i}!"
      {:ok, response} = Client.send(client_pid, 127, message)
      Logger.info("[QUIC_TEST] Response #{i}: #{inspect(response)}")
      assert response == message
      Process.sleep(50)
    end
  end
end
