defmodule TracesTest do
  alias Codec.State.Trie
  alias IO.ANSI
  alias Jamixir.Genesis
  alias System.State
  import TestVectorUtil
  use ExUnit.Case
  alias Util.Logger
  import Util.Hex

  setup_all do
    RingVrf.init_ring_context()
    # uncomment if you want to get trace files

    # System.put_env("PVM_TRACE", "true")
    :ok
  end

  def trace_enabled?, do: System.get_env("PVM_TRACE") == "true"

  @ignore_fields []

  def traces_path(mode), do: "traces/#{mode}"
  def testnet_path(mode), do: "data/#{mode}/state_transitions"

  oficial = %{
    user: "davxy",
    repo: "jam-test-vectors",
    branch: "master",
    path: &__MODULE__.traces_path/1,
    block_range: 1..100,
    modes: ["fallback", "safrole", "storage_light", "preimages_light", "storage", "preimages"]
  }

  _jam_duna = %{
    user: "jamixir",
    repo: "jamtestnet",
    branch: "master",
    path: &__MODULE__.testnet_path/1,
    block_range: 12..47,
    modes: ["generic", "assurances", "orderedaccumulation"]
  }

  def block_path(config, mode), do: "#{config[:path]}/#{mode}"

  # add jam_duna to the list of configs if you want to test it
  configs = [oficial]

  for config <- configs do
    describe "blocks and states" do
      for mode <- config[:modes] do
        @tag mode: mode
        @tag timeout: :infinity
        @tag config: config
        @tag :slow
        test "#{mode} mode block import", %{mode: mode, config: config} do
          {failed_blocks, _} =
            for block_number <- config[:block_range], reduce: {[], nil} do
              {failed_blocks, pre_state} ->
                if trace_enabled?() do
                  System.put_env("TRACE_NAME", "block-#{block_number}")
                end

                Logger.info("🧱 Processing block #{block_number}")
                file = String.pad_leading("#{block_number}", 8, "0")

                {:ok, block_json} =
                  case fetch_and_parse_json(
                         "#{file}.json",
                         config[:path].(mode),
                         config[:user],
                         config[:repo],
                         config[:branch]
                       ) do
                    {:error, _} ->
                      throw("Error fetching #{file}.json")

                    any ->
                      any
                  end

                parent_hash = JsonDecoder.from_json(block_json[:block][:header][:parent])

                unless Storage.get(parent_hash),
                  do: Storage.put(parent_hash, Genesis.genesis_block_header())

                pre_state_trie = Trie.from_json(block_json[:pre_state][:keyvals])

                pre_state = if pre_state, do: pre_state, else: Trie.trie_to_state(pre_state_trie)

                block = Block.from_json(block_json[:block])
                expected_trie = Trie.from_json(block_json[:post_state][:keyvals])

                case State.add_block(pre_state, block) do
                  {:ok, new_state} ->
                    Storage.put(block.header)
                    Logger.info("🔄 State Updated successfully")
                    expected_state = Trie.trie_to_state(expected_trie)
                    Logger.info("🔍 Comparing state")

                    %{data: new_state_trie} = Trie.serialize(new_state)

                    for {k, v} <- new_state_trie do
                      case Map.get(expected_trie, k) do
                        nil ->
                          Logger.error("not found in expected trie: #{b16(k)} => #{b16(v)}")

                        v2 when v2 != v ->
                          Logger.error(
                            "diffent in expected trie: #{b16(k)} => \n#{b16(v)}\n#{b16(v2)}"
                          )

                        _ ->
                          true
                      end
                    end

                    for {k, v} <- expected_trie do
                      case Map.get(new_state_trie, k) do
                        nil ->
                          Logger.error("not found in new state trie: #{b16(k)} => #{b16(v)}")

                        v2 when v2 != v ->
                          Logger.error(
                            "diffent in new state trie: #{b16(k)} => \n#{b16(v)}\n#{b16(v2)}"
                          )

                        _ ->
                          true
                      end
                    end

                    if new_state_trie != expected_trie do
                      raise "error"

                      failed_fields =
                        for field <- Utils.list_struct_fields(System.State), reduce: [] do
                          acc ->
                            if field in @ignore_fields do
                              acc
                            else
                              expected = Map.get(expected_state, field)
                              new = Map.get(new_state, field)

                              if expected != new do
                                Logger.info("❌ Field #{field} mismatch")
                                Logger.info("Expected: #{inspect(expected)}")
                                Logger.info("New: #{inspect(new)}")
                                acc ++ [field]
                              else
                                acc
                              end
                            end
                        end

                      if failed_fields == [] do
                        {failed_blocks, new_state}
                      else
                        {failed_blocks ++ [{block_number, failed_fields}], nil}
                      end
                    else
                      {failed_blocks, new_state}
                    end

                  {:error, _, error} ->
                    Logger.info("#{ANSI.red()} Error processing block: #{error}")

                    {failed_blocks ++ [{block_number, error}], nil}
                end
            end

          assert failed_blocks == []
          Logger.info("🎉 All blocks and states are correct")
        end
      end
    end
  end
end
