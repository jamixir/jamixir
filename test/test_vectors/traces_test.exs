defmodule TracesTest do
  alias Codec.State.Trie
  alias IO.ANSI
  alias System.State
  import TestVectorUtil
  import Jamixir.Factory
  use ExUnit.Case
  use Codec.Encoder
  require Logger

  setup_all do
    RingVrf.init_ring_context()
    # uncomment if you want to get trace files

    # System.put_env("PVM_TRACE", "true")
    :ok
  end

  def trace_enabled?, do: System.get_env("PVM_TRACE") == "true"

  @ignore_fields [:validator_statistics]
  @user "davxy"
  @repo "jam-test-vectors"

  def block_path(mode), do: "traces/#{mode}"

  # "reports-l0"
  describe "blocks and states" do
    for mode <- ["reports-l0"] do
      @tag mode: mode
      @tag timeout: :infinity
      # @tag :full_vectors
      test "#{mode} mode block import", %{mode: mode} do
        failed_blocks =
          for block_number <- 5..8, reduce: [] do
            failed_blocks ->
              if trace_enabled?() do
                System.put_env("TRACE_NAME", "block-#{block_number}")
              end

              Logger.info("🧱 Processing block #{block_number}")
              file = String.pad_leading("#{block_number}", 8, "0")

              {:ok, block_json} =
                case fetch_and_parse_json("#{file}.json", block_path(mode), @user, @repo) do
                  {:error, _} ->
                    throw("Error fetching #{file}.json")

                  any ->
                    any
                end

              parent_hash = JsonDecoder.from_json(block_json[:block][:header][:parent])

              unless Storage.get(parent_hash),
                do: Storage.put(parent_hash, build(:header, timeslot: 0))

              pre_state_trie = Trie.from_json(block_json[:pre_state][:keyvals])

              # extra_trie =
              #   Map.filter(pre_state_trie, fn {<<k::8, _::binary>>, _} ->
              #     k == 0 or k == 255
              #   end)

              # Application.put_env(:jamixir, :extra_trie, extra_trie)

              pre_state = Trie.trie_to_state(pre_state_trie)
              reserialized = Trie.serialize(pre_state)

              if reserialized != pre_state_trie do
                IO.inspect(pre_state.services[0].storage, label: "Storage")

                for {key, value} <- pre_state_trie, reserialized[key] != value do
                  Logger.info("❌ Original Key mismatch")
                  Logger.info("Key: #{inspect(key)}")
                  Logger.info("Expected: #{inspect(value)}")
                  Logger.info("New: #{inspect(reserialized[key])}")
                end

                for {key, value} <- reserialized, pre_state_trie[key] != value do
                  Logger.info("❌ New Key mismatch")
                  Logger.info("Key: #{inspect(key)}")
                  Logger.info("Expected: #{inspect(value)}")
                  Logger.info("New: #{inspect(pre_state_trie[key])}")
                end

                # Logger.info("❌ Pre-state mismatch")
                # Logger.info("Expected: #{inspect(pre_state_trie)}")
                # Logger.info("New: #{inspect(Trie.serialize(pre_state))}")
                assert false
              end

              block = Block.from_json(block_json[:block])
              expected_trie = Trie.from_json(block_json[:post_state][:keyvals])

              case State.add_block(pre_state, block) do
                {:ok, new_state} ->
                  Storage.put(block.header)
                  Logger.info("🔄 State Updated successfully")
                  new_state
                  Logger.info("🔍 Comparing state")
                  # assert Trie.serialize(new_state) == expected_trie
                  expected_state = Trie.trie_to_state(expected_trie)

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
                    failed_blocks
                  else
                    failed_blocks ++ [{block_number, failed_fields}]
                  end

                {:error, _, error} ->
                  Logger.info("#{ANSI.red()} Error processing block: #{error}")

                  failed_blocks ++ [{block_number, error}]
              end
          end

        assert failed_blocks == []
        Logger.info("🎉 All blocks and states are correct")
      end
    end
  end
end
