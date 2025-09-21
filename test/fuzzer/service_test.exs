defmodule Jamixir.FuzzerTest do
  use ExUnit.Case
  require Logger
  alias Codec.State.Trie
  alias Codec.State.Trie.SerializedState
  alias Jamixir.Fuzzer.{Client, Service}
  alias Jamixir.Genesis
  alias Jamixir.Meta
  alias Storage
  alias System.State
  alias System.State.ServiceAccount
  alias Util.Hash
  import Jamixir.Factory
  import Codec.Encoder
  import TestVectorUtil
  import Util.Hex

  @socket_path "/tmp/jam_conformance.sock"
  @conformance_path "../jam-conformance"

  setup do
    # if File.exists?(@socket_path), do: File.rm!(@socket_path)

    Task.start_link(fn -> Service.accept(@socket_path) end)

    # Give it a moment to start
    Process.sleep(100)

    {:ok, client} = Client.connect(@socket_path)
    Client.send_peer_info(client, Meta.name(), {0, 1, 0}, {1, 0, 0})
    Client.receive_message(client)

    on_exit(fn ->
      # Client.disconnect(client)
      # if File.exists?(@socket_path), do: File.rm!(@socket_path)
      Storage.remove_all()
    end)

    {:ok, client: client}
  end

  describe "peer_info handler" do
    test "handles basic peer info exchange", %{client: client} do
      assert :ok = Client.send_peer_info(client, Meta.name(), {0, 1, 0}, {1, 0, 0})
      assert {:ok, :peer_info, data} = Client.receive_message(client)

      assert %{name: name, jam_version: jam_version, app_version: app_version} = data
      assert name == Meta.name()
      assert app_version == Meta.app_version()
      assert jam_version == Meta.jam_version()
    end
  end

  describe "get_state handler" do
    test "handles get_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state

      header_hash = Hash.one()
      Storage.put(header_hash, state)

      assert :ok = Client.send_get_state(client, header_hash)
      assert {:ok, :state, incoming_state} = Client.receive_message(client)

      # clear service original storage map, as it is lost on encoding process
      old_storage = state.services[1].storage

      service = %ServiceAccount{
        state.services[1]
        | storage: HashedKeysMap.new_without_original(old_storage.original_map)
      }

      state = %State{state | services: %{1 => service}}

      for {key, value} <- Map.from_struct(state) do
        assert value == Map.get(incoming_state, key)
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
    setup do
      tiny_configs()
    end

    test "handles set_state request", %{client: client} do
      state = build(:genesis_state_with_safrole).state
      # Clear storage from all services
      state = %{
        state
        | services:
            for {service_id, service_account} <- state.services, into: %{} do
              {service_id, %{service_account | storage: HashedKeysMap.new()}}
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
  end

  describe "test vectors with fuzzer" do
    setup do
      tiny_configs()
    end

    @fuzz_path "#{@conformance_path}/fuzz-reports"
    @base_path "#{@fuzz_path}/0.7.0/traces/"
    @all_traces (case File.ls(@base_path) do
                   {:ok, files} ->
                     files |> Enum.filter(fn file -> String.match?(file, ~r/^\d+/) end)

                   {:error, _} ->
                     []
                 end)

    # Focused test for debugging a specific failing case
    @tag :focused_debug
    test "debug specific failing case 1757406356", %{client: client} do
      dir = "#{@base_path}/1757406356/"
      test_case(client, dir)
    end

    for case_dir <- @all_traces do
      dir = "#{@base_path}/#{case_dir}/"

      @tag dir: dir
      @tag :fuzzer
      @tag :slow
      test "archive fuzz blocks #{dir}", %{client: client, dir: dir} do
        test_case(client, dir)
      end
    end

    @modes ["fallback", "safrole", "storage_light", "preimages_light", "storage", "preimages"]
    @tag :perf
    @tag :slow
    test "Block Import Performance Bench", %{client: client} do
      test_dict =
        for mode <- @modes,
            into: %{},
            do:
              {"fuzzer 100 blocks #{mode}",
               fn -> test_case(client, "../jam-test-vectors/traces/#{mode}") end}

      # Map.values(test_dict) |> Enum.each(& &1.())
      Benchee.run(test_dict)
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

    test "return response when block import fails", %{client: client, block_json: block_json} do
      block = Block.from_json(block_json[:block])
      block = put_in(block.header.prior_state_root, Hash.random())
      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :error, _} = Client.receive_message(client)
    end

    test "return response when block parent state is invalid", %{
      client: client,
      block_json: block_json
    } do
      block = Block.from_json(block_json[:block])
      block = put_in(block.header.parent_hash, Hash.random())
      assert :ok = Client.send_import_block(client, block)
      assert {:ok, :error, error} = Client.receive_message(client)
      assert String.contains?(error, "parent_state_not_found")
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

  describe "protocol v1 examples" do
    @examples_path "#{@conformance_path}/fuzz-proto/examples/v1/"
    test "PeerInfo", %{client: client} do
      <<_::8, bin::binary>> = File.read!("#{@examples_path}/faulty/00000000_fuzzer_peer_info.bin")
      assert :ok = Client.send_message(client, :peer_info, bin)

      assert {:ok, :peer_info, data} = Client.receive_message(client)
      assert %{name: name, jam_version: jam_version, app_version: app_version} = data
      assert name == Meta.name()
      assert app_version == Meta.app_version()
      assert jam_version == Meta.jam_version()
    end

    test "Initialize", %{client: client} do
      <<_::8, bin::binary>> =
        File.read!("#{@examples_path}/faulty/00000001_fuzzer_initialize.bin")

      <<_::8, exp_root::binary>> =
        File.read!("#{@examples_path}/faulty/00000001_target_state_root.bin")

      assert :ok = Client.send_message(client, :initialize, bin)
      assert {:ok, :state_root, root} = Client.receive_message(client)

      assert b16(root) == b16(exp_root)
    end

    test "Error on import", %{client: client} do
      <<_::8, bin::binary>> =
        File.read!("#{@examples_path}/faulty/00000001_fuzzer_initialize.bin")

      assert :ok = Client.send_message(client, :initialize, bin)
      assert {:ok, :state_root, _} = Client.receive_message(client)

      <<_::8, bin::binary>> =
        File.read!("#{@examples_path}/faulty/00000002_fuzzer_import_block.bin")

      assert :ok = Client.send_message(client, :import_block, bin)
      assert {:ok, :error, error} = Client.receive_message(client)
      assert error == "Chain error: block execution failure: preimage_unneeded"
    end

    @tag :slow
    @tag :fuzzerv1
    test "Import all blocks", %{client: client} do
      for type <- ["faulty", "forks", "no_forks"] do
        for [fuzzer_file, target_file] <-
              files_in_dir("#{@examples_path}/#{type}/", ~r/.+\.bin/) |> Enum.chunk_every(2),
            # # 29 example is broken for purpose (https://github.com/davxy/jam-conformance/issues/82)
            not (type == "faulty" and fuzzer_file =~ ~r/29/) do
          Logger.info("Testing #{type} #{fuzzer_file}")

          <<_::8, bin::binary>> = File.read!("#{@examples_path}/#{type}/#{fuzzer_file}")
          <<_::8, exp_result::binary>> = File.read!("#{@examples_path}/#{type}/#{target_file}")

          if fuzzer_file =~ ~r/peer_info/ do
            assert :ok = Client.send_message(client, :peer_info, bin)

            assert {:ok, :peer_info, data} = Client.receive_message(client)
            assert %{name: _, jam_version: _, app_version: _} = data
          else
            if fuzzer_file =~ ~r/initialize/ do
              assert :ok = Client.send_message(client, :initialize, bin)
              assert {:ok, :state_root, root} = Client.receive_message(client)
              assert root == exp_result
            else
              if fuzzer_file =~ ~r/import_block/ do
                block_bin = bin
                assert :ok = Client.send_message(client, :import_block, block_bin)

                case Client.receive_message(client) do
                  {:ok, :state_root, root} ->
                    if root != exp_result do
                      <<_::8, bin::binary>> =
                        File.read!("#{@examples_path}/#{type}/00000030_target_state.bin")

                      {:ok, exp_state_trie, _} = Trie.from_binary(bin)

                      {block, _} = Block.decode(block_bin)
                      assert :ok = Client.send_message(client, :get_state, h(e(block.header)))

                      {:ok, :state, post_state} = Client.receive_message(client)
                      post_state_trie = Trie.serialize(post_state)

                      compare_tries(exp_state_trie, post_state_trie)
                      assert root == exp_result
                    end

                  {:ok, :error, error} ->
                    assert String.contains?(error, "Chain error")
                    assert String.contains?(exp_result, "Chain error")
                end
              end
            end
          end
        end
      end
    end
  end

  defp block_json(file),
    do: fetch_and_parse_json(file, "traces/fallback", "davxy", "jam-test-vectors", "master")

  defp test_block(client, file, root, dir) do
    Logger.info("Processing block #{file} with root #{b16(root)}")

    <<_::b(hash), rest::binary>> = File.read!("#{dir}/#{file}")

    {:ok, _pre_state, rest} = Trie.from_binary(rest)
    before_size = byte_size(rest)
    {block, rest} = Block.decode(rest)
    block_bin_size = before_size - byte_size(rest)
    assert block_bin_size == byte_size(e(block))
    <<exp_post_state_root::b(hash), rest::binary>> = rest
    {:ok, exp_post_state_trie, _} = Trie.from_binary(rest)

    assert :ok = Client.send_message(client, :import_block, e(block))
    assert {:ok, type, resp} = Client.receive_message(client, :infinity)

    if type == :error do
      Util.Logger.info("Block transition failed because of #{resp}")
    else
      assert :ok = Client.send_message(client, :get_state, h(e(block.header)))
      assert {:ok, :state, post_state} = Client.receive_message(client)

      post_state_trie = Trie.serialize(post_state)
      compare_tries(exp_post_state_trie, post_state_trie)
      assert b16(exp_post_state_root) == b16(resp)
    end

    resp
  end

  defp compare_tries(exp_post_state_trie, post_state_trie) do
    if exp_post_state_trie != post_state_trie do
      Util.Logger.info("Expected trie doesn't match trie")

      for {k, exp_v} <- exp_post_state_trie.data do
        v = Map.get(post_state_trie.data, k)

        if v != exp_v do
          Util.Logger.info("key doesn't match #{b16(k)}")
          Util.Logger.info("v=#{b16(v || "")}\nexp_v=#{b16(exp_v || "")}")

          key = Trie.octet31_to_key(k)
          {exp_obj, _} = Trie.decode_value(key, exp_v)
          {obj, _} = Trie.decode_value(key, v)
          assert %{b16(k) => exp_obj} == %{b16(k) => obj}
        end
      end
    end
  end

  defp test_case(client, dir) do
    Util.Logger.info("Testing case #{dir}")
    files = files_in_dir(dir)
    [f1 | all_but_first] = files
    <<_state_root::b(hash), rest::binary>> = File.read!("#{dir}/#{f1}")
    {:ok, _pre_state, rest} = Trie.from_binary(rest)
    {block, rest} = Block.decode(rest)
    <<_state_root::b(hash), rest::binary>> = rest

    {:ok, b1_post_state, _rest} = Trie.from_binary(rest)

    message = e(block.header) <> Trie.to_binary(b1_post_state)
    assert :ok = Client.send_message(client, :initialize, message)
    assert {:ok, :state_root, root} = Client.receive_message(client)

    state = Trie.deserialize(b1_post_state)

    assert b1_post_state == Trie.serialize(state)
    assert root == Trie.state_root(state)

    root =
      for file <- all_but_first, reduce: root do
        root -> test_block(client, file, root, dir)
      end

    Logger.warning("Passing test case #{dir} with root #{b16(root)}")
  end

  defp files_in_dir(dir, filter \\ ~r/\d+\.bin/) do
    File.ls!(dir)
    |> Enum.filter(fn file -> String.match?(file, filter) end)
    |> Enum.sort()
  end

  defp tiny_configs do
    old_config = Jamixir.config()
    new_config = put_in(old_config, [:ignore_refinement_context], true)
    new_config = put_in(new_config, [:ignore_future_time], true)
    Application.put_env(:jamixir, Jamixir, new_config)

    on_exit(fn ->
      Application.put_env(:jamixir, Jamixir, old_config)
    end)
  end
end
