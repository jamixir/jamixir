defmodule ListenerTest do
  use ExUnit.Case, async: false
  import TestHelper

  alias Network.{Connection}
  import ExUnit.Assertions


  @dummy_protocol_id 242
  @port 9997
  setup_all do
    start_supervised!({Network.Listener, port: @port})
    :ok
  end

  describe "multiple connections to single listener" do
    test "listener can accept connections from three clients and ConnectionManager tracks them uniquely" do
      port = @port

      # Start three clients, each with a unique key
      keys = Enum.map(1..3, fn _ -> Util.Hash.random() end)

      clients =
        Enum.map(keys, fn key ->
          {:ok, pid} =
            Network.ConnectionManager.start_outbound_connection(key, {127, 0, 0, 1}, port)

          pid
        end)

      Process.sleep(100)
      Enum.each(clients, fn pid -> wait(fn -> Process.alive?(pid) end) end)

      # Assert all client PIDs are unique
      assert Enum.uniq(clients) == clients

      # Assert ConnectionManager tracks all three connections with unique PIDs
      conn_map = Network.ConnectionManager.get_connections()
      # IO.inspect(conn_map)
      tracked_pids = Enum.map(keys, &conn_map[&1])
      assert Enum.sort(Enum.uniq(tracked_pids)) == Enum.sort(clients)

      responses =
        for {client, idx} <- Enum.with_index(clients, 1) do
          msg = "hello_from_client_#{idx}"
          {:ok, resp} = Connection.send(client, @dummy_protocol_id, msg)
          resp
        end

      for {resp, idx} <- Enum.with_index(responses, 1) do
        expected_prefix = "hello_from_client_#{idx}"
        assert String.starts_with?(resp, expected_prefix)
      end

      msg_len = byte_size("hello_from_client_1")

      server_pids =
        Enum.map(responses, fn resp ->
          <<_msg::binary-size(msg_len), pid_bin::binary>> = resp
          :erlang.binary_to_term(pid_bin)
        end)

      assert length(Enum.uniq(server_pids)) == 3

      all_conncetions_pids = Network.ConnectionManager.get_connections() |> Map.values()
      assert length(all_conncetions_pids) == 6 # 3 clients  + 3 servers

      Enum.each(server_pids, fn pid ->
        assert pid in all_conncetions_pids
      end)
    end
  end
end
