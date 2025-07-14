defmodule TracesTest do
  alias Codec.State.Trie
  alias IO.ANSI
  alias System.State
  import TestVectorUtil
  import Jamixir.Factory
  use ExUnit.Case
  require Logger

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
    block_range: 1..42,
    modes: ["fallback", "safrole", "reports-l0", "reports-l1"]
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
                  do: Storage.put(parent_hash, build(:header, timeslot: 0))

                pre_state_trie = Trie.from_json(block_json[:pre_state][:keyvals])

                pre_state = if pre_state, do: pre_state, else: Trie.trie_to_state(pre_state_trie)

                block = Block.from_json(block_json[:block])
                expected_trie = Trie.from_json(block_json[:post_state][:keyvals])

                case State.add_block(pre_state, block) do
                  {:ok, new_state} ->
                    Storage.put(block.header)
                    Logger.info("🔄 State Updated successfully")
                    expected_state = Trie.trie_to_state(expected_trie)

                    #
                    Logger.info("🔍 Comparing state")
                    # uncomment to delete statistics from state trie
                    # |> Map.delete(<<13, 0::30*8>>)
                    %{data: trie1} = Trie.serialize(new_state)
                    # |> Map.delete(<<13, 0::30*8>>)
                    trie2 = expected_trie

                    if trie1 != trie2 do
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
