defmodule TestnetBlockImporterTest do
  alias IO.ANSI
  alias System.State
  alias Util.Hash
  import TestVectorUtil
  use ExUnit.Case
  require Logger
  import Mox

  @first_epoch 395_479
  @last_epoch 395_483

  setup_all do
    RingVrf.init_ring_context()

    # Application.put_env(:jamixir, :header_seal, HeaderSealMock)

    Application.put_env(:jamixir, :original_modules, [
      System.State.Safrole,
      :validate,
      System.Validators.Safrole,
      Block.Extrinsic.TicketProof,
      Util.Collections,
      Util.Time
    ])

    on_exit(fn ->
      # Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      Application.delete_env(:jamixir, Constants)
      Application.delete_env(:jamixir, :original_modules)
    end)

    :ok
  end

  @ignore_fields [:accumulation_history, :recent_history, :safrole]
  @safrole_path "./traces/safrole/jam_duna"
  @state_path "#{@safrole_path}/state_snapshots/"
  @block_path "#{@safrole_path}/blocks/"
  @user "jamixir"
  @repo "jamtestnet"

  describe "blocks and states" do
    # waiting for correctnes of other party side
    @tag :skip
    test "jam-dune" do
      {:ok, genesis_json} = fetch_and_parse_json("genesis.json", @state_path, @user, @repo)

      stub(HeaderSealMock, :do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: Hash.zero()}}
      end)

      state = Codec.State.from_json(genesis_json)

      Enum.reduce(@first_epoch..@last_epoch, state, fn epoch, state ->
        Enum.reduce(0..(Constants.epoch_length() - 1), state, fn timeslot, state ->
          Logger.info("Processing block #{epoch}:#{timeslot}...")
          timeslot = String.pad_leading("#{timeslot}", 3, "0")

          block_bin = fetch_binary("#{epoch}_#{timeslot}.bin", @block_path, @user, @repo)

          {block, _} = Block.decode(block_bin)

          {:ok, json} =
            fetch_and_parse_json("#{epoch}_#{timeslot}.json", @state_path, @user, @repo)

          expected_state = Codec.State.from_json(json)

          new_state =
            case State.add_block(state, block) do
              {:ok, s} ->
                s

              {:error, _, error} ->
                Logger.info("#{ANSI.red()} Error processing block #{epoch}:#{timeslot}: #{error}")
                state
            end

          Logger.info("#{ANSI.green()} Comparing state...")

          for field <- Utils.list_struct_fields(System.State) do
            Logger.info("Checking field #{field}...")

            unless Enum.find(@ignore_fields, &(&1 == field)) do
              assert Map.get(expected_state, field) == Map.get(new_state, field)
            end
          end

          new_state
        end)
      end)
    end
  end
end
