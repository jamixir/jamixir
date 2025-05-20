defmodule TestnetBlockImporterTest do
  alias Codec.State.Trie
  alias Block.Header
  alias Codec.State.Json
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

  @ignore_fields []
  @user "davxy"
  @repo "jam-test-vectors"

  def block_path(mode), do: "traces/#{mode}"

  describe "blocks and states" do
    setup do
      for h <- [
            <<0x3E01E6ED1C5956AA7CEAC27848ED6F1D62CC4A9E940DD8C761891CB55749890C::hash()>>
          ] do
        Storage.put(h, build(:header, timeslot: 0))
      end

      :ok
    end

    # "reports-l0"
    for mode <- ["fallback", "safrole"] do
      @tag mode: mode
      test "#{mode} mode block import", %{mode: mode} do
        for block <- 1..42 do
          if trace_enabled?() do
            System.put_env("TRACE_NAME", "block-#{block}")
          end

          Logger.info("🧱 Processing block #{block}")
          file = String.pad_leading("#{block}", 8, "0")

          {:ok, block_json} =
            case fetch_and_parse_json("#{file}.json", block_path(mode), @user, @repo) do
              {:error, _} ->
                throw("Error fetching #{file}.json")

              any ->
                any
            end

          pre_state_trie = Trie.from_json(block_json[:pre_state][:keyvals])

          extra_trie =
            Map.filter(pre_state_trie, fn {<<k::8, _::binary>>, _} ->
              k == 0 or k == 255
            end)

          Application.put_env(:jamixir, :extra_trie, extra_trie)

          pre_state = Trie.trie_to_state(pre_state_trie)
          block = Block.from_json(block_json[:block])
          expected_trie = Trie.from_json(block_json[:post_state][:keyvals])
          expected_state = Trie.trie_to_state(expected_trie)

          new_state =
            case State.add_block(pre_state, block) do
              {:ok, s} ->
                Storage.put(block.header)
                Logger.info("🔄 State Updated successfully")
                s

              {:error, _, error} ->
                Logger.info("#{ANSI.red()} Error processing block #{block}: #{error}")

                pre_state
            end

          Logger.info("🔍 Comparing state")

          for field <- Utils.list_struct_fields(System.State) do
            unless Enum.find(@ignore_fields, &(&1 == field)) do
              expected = Map.get(expected_state, field)
              new = Map.get(new_state, field)
              assert expected == new
              # Logger.info("✅ Field #{field} match")
            end
          end
        end

        Logger.info("🎉 All blocks and states are correct")
      end
    end
  end
end
