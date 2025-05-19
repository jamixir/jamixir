defmodule TestnetBlockImporterTest do
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
  @genesis_path "chainspecs/state_snapshots"
  @user "jamixir"
  @repo "jamtestnet"

  def state_path(mode), do: "data/#{mode}/state_snapshots"
  def blocks_path(mode), do: "data/#{mode}/blocks"

  describe "blocks and states" do
    setup do
      for h <- [
            <<0x2F0F2E36394B4EBF80DE3D63C7D447013F05398A03FEDF179113018FC6F6DCB7::hash()>>,
            <<0x03C6255F4EED3DB451C775E33E2D7EF03A1BA7FB79CD525B5DDF650703CCDB92::hash()>>
          ] do
        Storage.put(h, build(:header, timeslot: 0))
      end

      :ok
    end

    for mode <- ["fallback", "safrole", "reports-l0"] do
      @tag mode: mode
      test "#{mode} mode block import", %{mode: mode} do
        {:ok, genesis_json} =
          case fetch_and_parse_json("genesis.json", state_path(mode), @user, @repo) do
            {:error, _} ->
              fetch_and_parse_json("genesis-tiny.json", @genesis_path, @user, @repo)

            any ->
              any
          end

        state = %State{}

        first_time = 1

        Enum.reduce(first_time..(first_time + 2), state, fn epoch, state ->
          Enum.reduce(0..(Constants.epoch_length() - 1), state, fn timeslot, state ->
            if trace_enabled?() do
              System.put_env("TRACE_NAME", "#{mode}_#{epoch}:#{timeslot}")
            end

            Logger.info("🧱 Processing block #{epoch}:#{timeslot}")
            timeslot = String.pad_leading("#{timeslot}", 3, "0")

            block_bin = fetch_binary("#{epoch}_#{timeslot}.bin", blocks_path(mode), @user, @repo)

            {block, _} = Block.decode(block_bin)

            {:ok, json} =
              fetch_and_parse_json("#{epoch}_#{timeslot}.json", state_path(mode), @user, @repo)

            expected_state = Json.decode(json)

            new_state =
              case State.add_block(state, block) do
                {:ok, s} ->
                  Storage.put(block.header)
                  Logger.info("🔄 State Updated successfully")
                  s

                {:error, _, error} ->
                  Logger.info(
                    "#{ANSI.red()} Error processing block #{epoch}:#{timeslot}: #{error}"
                  )

                  state
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

            new_state
          end)
        end)

        Logger.info("🎉 All blocks and states are correct")
      end
    end
  end
end
