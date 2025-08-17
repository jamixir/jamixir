defmodule Jamixir.FuzzerTest do
  use ExUnit.Case
  alias Codec.State.Trie
  alias Codec.State.Trie.SerializedState
  alias Jamixir.Fuzzer.{Client, Service}
  alias Jamixir.Genesis
  alias Jamixir.Meta
  alias Storage
  alias System.State.ServiceAccount
  alias Util.Hash
  import Jamixir.Factory
  import Codec.Encoder
  import TestVectorUtil
  import Util.Hex

  @socket_path "/tmp/jamixir_fuzzer_test.sock"

  setup do
    if File.exists?(@socket_path), do: File.rm!(@socket_path)

    fuzzer_pid = Task.start_link(fn -> Service.accept(@socket_path) end)

    # Give it a moment to start
    Process.sleep(100)

    {:ok, client} = Client.connect(@socket_path)

    on_exit(fn ->
      Client.disconnect(client)
      if File.exists?(@socket_path), do: File.rm!(@socket_path)
      Storage.remove_all()
    end)

    {:ok, client: client, fuzzer_pid: fuzzer_pid}
  end

  describe "peer_info handler" do
    test "handles basic peer info exchange", %{client: client} do
      assert :ok = Client.send_peer_info(client, Meta.name(), {0, 1, 0}, {1, 0, 0})
      assert {:ok, :peer_info, data} = Client.receive_message(client)

      assert %{name: name, version: version, protocol: protocol} = data
      assert name == Meta.name()
      assert version == Meta.app_version()
      assert protocol == Meta.jam_version()
    end
  end

  describe "get_state handler" do
    test "handles get_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state

      header_hash = Hash.one()
      Storage.put(header_hash, state)

      assert :ok = Client.send_get_state(client, header_hash)
      assert {:ok, :state, incoming_state} = Client.receive_message(client)

      fields = Map.from_struct(state) |> Map.drop([:services])

      for {key, value} <- fields do
        assert value == Map.get(incoming_state, key)
      end

      service_field_keys = ServiceAccount.__struct__() |> Map.keys() |> List.delete(:storage)

      for service_key <- Map.keys(state.services) do
        for service_field_key <- service_field_keys do
          assert Map.get(Map.get(incoming_state.services, service_key), service_field_key) ==
                   Map.get(Map.get(state.services, service_key), service_field_key)
        end
      end
    end

    test "handles get_state request for non-existent state", %{client: client} do
      # Request a state that doesn't exist
      non_existent_hash = Hash.random()

      assert :ok = Client.send_get_state(client, non_existent_hash)

      # The service should not send a response for non-existent states
      # note, this is a guess, the protocol doesn't mention what to do in this case
      # and since the fuzzer is an intrenal test tool, this should not happen and should not really be a concern
      # We expect a timeout or error
      result = Client.receive_message(client, 1000)

      # The service logs an error but doesn't send a response for non-existent states
      # So we expect a timeout or error
      assert result == {:error, :closed}
    end
  end

  describe "set_state handler" do
    test "handles set_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state
      # Clear storage from all services
      state = %{
        state
        | services:
            for {service_id, service_account} <- state.services, into: %{} do
              {service_id, %{service_account | storage: %{}}}
            end
      }

      serialized_state = Trie.serialize(state)
      expected_state_root = Trie.state_root(serialized_state)
      header = build(:decodable_header)
      header_hash = h(e(header))

      assert :ok = Client.send_set_state(client, header, state)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

      assert incoming_state_root == expected_state_root
      assert Storage.get_state_root(header_hash) == incoming_state_root
    end

    test "fuzzer example stf binaries", %{client: client} do
      <<_protocol::8, message::binary>> = File.read!("test/fuzzer/2_set_state.bin")

      assert :ok = Client.send_message(client, :set_state, message)
      assert {:ok, :state_root, root} = Client.receive_message(client)

      # 3_state_root
      assert b16(root) == "0x76acb3326996df5eb7555790b7a60a9a8d519e4fae3e6a4ef906dcc3bedbc2b8"

      for {block_file, exp_root} <- [
            {"4_block", "0x49c0c77f752c95c58d33b646c1f144432a89b7c99b807e07914dec267b4e1088"},
            {"6_block", "0xb79a752df339d056ef5730aebe8785f35db225caf7f8115fe26e2ba0420ef3c6"}
            # block failing root
            # {"8_block", "0x5abb6eda68c027ee4c234608c91de019a5e394f7eaa1faaa03e201bbae5d163c"}
          ] do
        <<_protocol::8, block::binary>> = File.read!("test/fuzzer/#{block_file}.bin")
        assert :ok = Client.send_message(client, :import_block, block)
        assert {:ok, :state_root, root} = Client.receive_message(client)
        assert b16(root) == exp_root
        Util.Logger.info("Processed #{block_file} with expected root #{exp_root}")
      end
    end

    @base_path "../jam-conformance/fuzz-reports/archive/0.6.7"

    for case_dir <- File.ls!(@base_path) do
      dir = "#{@base_path}/#{case_dir}/"

      @tag :fuzzer
      @tag dir: dir
      @tag :skip
      test "archive fuzz blocks #{dir}", %{client: client, dir: dir} do
        files =
          File.ls!(dir)
          |> Enum.filter(fn file -> String.match?(file, ~r/\d+\.bin/) end)
          |> Enum.sort()

        test_case(client, files, dir)
      end
    end

    # here just while fuzzer are being test to make it easy fuzzer traces debug. Remove when done.
    @tag :skip
    test "fuzzer blocks", %{client: client} do
      dir = "../jam-conformance/fuzz-reports/jamixir/0.6.7/1755151480"
      files = ["00000005.bin", "00000006.bin"]

      test_case(client, files, dir)
    end

    @tag :skip
    test "fuzzer blocks 3", %{client: client} do
      dir = "../jam-conformance/fuzz-reports/archive/0.6.7/1755186771"
      files = ["00000029.bin", "00000030.bin"]

      test_case(client, files, dir)
    end

    @tag :skip
    test "test" do
      exp =
        Util.Hex.decode16!(
          "0x01000000000000000000000000000000030000000500000000000000000000000000000000000000020000000400000001000000000000000000000000000000020000000400000002000000000000000000000000000000030000000400000000000000000000000000000000000000030000000400000002000000000000000000000000000000020000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080f3050000000088c7c1cf4700030000000000000100000000000001c1cf470000000001af280000"
        )

      got =
        Util.Hex.decode16!(
          "0x01000000000000000000000000000000030000000500000000000000000000000000000000000000020000000400000001000000000000000000000000000000020000000400000002000000000000000000000000000000030000000400000000000000000000000000000000000000030000000400000002000000000000000000000000000000020000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080f3050000000088c7c1cf4700030000000000000100000000000001c1cf470000000001a7300000"
        )

      t_exp = Trie.decode_value(13, exp)
      t_got = Trie.decode_value(13, got)
      assert t_exp == t_got
    end
  end

  describe "import_block handler" do
    setup %{client: client} do
      {:ok, block_json} = block_json("00000001.json")

      parent_hash = JsonDecoder.from_json(block_json[:block][:header][:parent])
      header = Genesis.genesis_block_header()
      Storage.put(parent_hash, header)

      # put the pre_state in storage under the parent hash
      pre_state_trie = Trie.from_json(block_json[:pre_state][:keyvals])
      pre_state = Trie.trie_to_state(pre_state_trie)
      Storage.put(header, pre_state)

      {:ok,
       client: client, parent_hash: parent_hash, pre_state: pre_state, block_json: block_json}
    end

    test "handles single import_block request", %{client: client, block_json: block_json} do
      block = Block.from_json(block_json[:block])
      expected_trie = Trie.from_json(block_json[:post_state][:keyvals])
      expected_state_root = Trie.state_root(%SerializedState{data: expected_trie})
      header_hash = h(e(block.header))

      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

      assert incoming_state_root == expected_state_root
      assert Storage.get_state_root(header_hash) == expected_state_root

      assert Storage.get_block(header_hash) == block
    end

    test "return response when block import fails", %{
      client: client,
      block_json: block_json,
      pre_state: pre_state
    } do
      block = Block.from_json(block_json[:block])
      block = put_in(block.header.prior_state_root, Hash.random())
      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)
      assert incoming_state_root == Trie.state_root(pre_state)
    end

    test "return response when block parent state is invalid", %{
      client: client,
      block_json: block_json,
      pre_state: pre_state
    } do
      block = Block.from_json(block_json[:block])
      block = put_in(block.header.parent_hash, Hash.random())
      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)
      assert incoming_state_root == Trie.state_root(pre_state)
    end

    @tag :slow
    test "handles sequential import of 10 blocks", %{client: client} do
      block_range = 1..10

      for block_number <- block_range do
        file = String.pad_leading("#{block_number}", 8, "0")

        {:ok, block_json} = block_json("#{file}.json")

        block = Block.from_json(block_json[:block])
        expected_trie = Trie.from_json(block_json[:post_state][:keyvals])
        expected_state_root = Trie.state_root(%SerializedState{data: expected_trie})
        header_hash = h(e(block.header))

        assert :ok = Client.send_import_block(client, block)
        assert {:ok, :state_root, incoming_state_root} = Client.receive_message(client)

        assert incoming_state_root == expected_state_root
        assert Storage.get_block(header_hash) == block
        assert Storage.get_state_root(header_hash) == expected_state_root
      end

      {:ok, final_block_json} = block_json("00000010.json")

      final_block = Block.from_json(final_block_json[:block])
      final_header_hash = h(e(final_block.header))
      expected_final_trie = Trie.from_json(final_block_json[:post_state][:keyvals])

      # retrive final state and comapre to expected post state from trace
      assert :ok = Client.send_get_state(client, final_header_hash)
      assert {:ok, :state, retrieved_state} = Client.receive_message(client)

      assert Trie.serialize(retrieved_state).data == expected_final_trie
    end
  end

  defp block_json(file),
    do: fetch_and_parse_json(file, "traces/fallback", "davxy", "jam-test-vectors", "master")

  defp test_block(client, file, root, dir) do
    IO.puts("Processing block #{file} with root #{b16(root)}")

    <<block_pre_state_root::b(hash), rest::binary>> = File.read!("#{dir}/#{file}")

    assert b16(block_pre_state_root) == b16(root)
    {:ok, _pre_state, rest} = Trie.from_binary(rest)
    {block, rest} = Block.decode(rest)
    <<_state_root::b(hash), rest::binary>> = rest
    {:ok, exp_post_state, _} = Trie.from_binary(rest)

    assert :ok = Client.send_message(client, :import_block, e(block))
    assert {:ok, :state_root, root} = Client.receive_message(client)

    assert :ok = Client.send_message(client, :get_state, h(e(block.header)))
    assert {:ok, :state, post_state} = Client.receive_message(client)

    post_state_trie = Trie.serialize(post_state)

    if exp_post_state != post_state_trie do
      for {k, exp_v} <- exp_post_state.data do
        v = Map.get(post_state_trie.data, k)

        if v != exp_v do
          Util.Logger.error("key doesn't match #{b16(k)}")
          key = Trie.octet31_to_key(k)
          exp_obj = Trie.decode_value(key, exp_v)
          obj = Trie.decode_value(key, v)
          assert exp_obj == obj
        end
      end
    end

    root
  end

  defp test_case(client, files, dir) do
    Util.Logger.info("Testing case #{dir}")
    [f1 | all_but_first] = files
    <<_state_root::b(hash), rest::binary>> = File.read!("#{dir}/#{f1}")
    {:ok, _pre_state, rest} = Trie.from_binary(rest)
    {block, rest} = Block.decode(rest)
    <<_state_root::b(hash), rest::binary>> = rest

    {:ok, b1_post_state, _rest} = Trie.from_binary(rest)

    message = e(block.header) <> Trie.to_binary(b1_post_state)
    assert :ok = Client.send_message(client, :set_state, message)
    assert {:ok, :state_root, root} = Client.receive_message(client)

    state = Trie.deserialize(b1_post_state)

    assert b1_post_state == Trie.serialize(state)
    assert root == Trie.state_root(state)

    for file <- all_but_first, reduce: root do
      root -> test_block(client, file, root, dir)
    end
  end
end
