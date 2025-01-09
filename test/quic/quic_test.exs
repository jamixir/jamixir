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
    #   level: :debug,
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

    tasks = for i <- 1..1000 do
      Task.async(fn ->
        message = "Hello, server#{i}!"
        {:ok, response} = Client.send(client_pid, 127, message)
        Logger.info("[QUIC_TEST] Response #{i}: #{inspect(response)}")
        assert response == message
        i
      end)
    end

    results = Task.await_many(tasks, 5000)
    assert length(results) == 1000
  end
end
