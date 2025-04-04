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

    skip = ["assurances"]

    for mode <- ["fallback", "safrole", "assurances"] do
      if Enum.member?(skip, mode) do
        IO.puts(
          :stderr,
          IO.ANSI.yellow() <>
            "⚠️  Warning: #{mode} mode block import test is disabled" <> IO.ANSI.reset()
        )

        @tag :skip
      end

      @tag mode: mode
      test "#{mode} mode block import", %{mode: mode} do
        {:ok, genesis_json} =
          case fetch_and_parse_json("genesis.json", state_path(mode), @user, @repo) do
            {:error, _} ->
              fetch_and_parse_json("genesis-tiny.json", @genesis_path, @user, @repo)

            any ->
              any
          end

        state = Json.decode(genesis_json)

        first_time =
          if mode == "safrole" do
            108_489
          else
            1
          end

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

  test "duna block encoding" do
    h = %{
      parent: "0x0000000000000000000000000000000000000000000000000000000000000000",
      parent_state_root: "0x68d749b661c2a6414324a3b0e8dc53791f9c6da964b465d9745f7da819eb4592",
      extrinsic_hash: "0xdc080ad182cb9ff052a1ca8ecbc51164264efc7dd6debaaa45764950f843acb8",
      slot: 4_943_796,
      epoch_mark: %{
        entropy: "0x6f6ad2224d7d58aec6573c623ab110700eaca20a48dc2965d535e466d524af2a",
        tickets_entropy: "0x835ac82bfa2ce8390bb50680d4b7a73dfa2a4cff6d8c30694b24a605f9574eaf",
        validators: [
          %{
            bandersnatch: "0x5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d",
            ed25519: "0x3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29"
          },
          %{
            bandersnatch: "0x3d5e5a51aab2b048f8686ecd79712a80e3265a114cc73f14bdb2a59233fb66d0",
            ed25519: "0x22351e22105a19aabb42589162ad7f1ea0df1c25cebf0e4a9fcd261301274862"
          },
          %{
            bandersnatch: "0xaa2b95f7572875b0d0f186552ae745ba8222fc0b5bd456554bfe51c68938f8bc",
            ed25519: "0xe68e0cf7f26c59f963b5846202d2327cc8bc0c4eff8cb9abd4012f9a71decf00"
          },
          %{
            bandersnatch: "0x7f6190116d118d643a98878e294ccf62b509e214299931aad8ff9764181a4e33",
            ed25519: "0xb3e0e096b02e2ec98a3441410aeddd78c95e27a0da6f411a09c631c0f2bea6e9"
          },
          %{
            bandersnatch: "0x48e5fcdce10e0b64ec4eebd0d9211c7bac2f27ce54bca6f7776ff6fee86ab3e3",
            ed25519: "0x5c7f34a4bd4f2d04076a8c6f9060a0c8d2c6bdd082ceb3eda7df381cb260faff"
          },
          %{
            bandersnatch: "0xf16e5352840afb47e206b5c89f560f2611835855cf2e6ebad1acc9520a72591d",
            ed25519: "0x837ce344bc9defceb0d7de7e9e9925096768b7adb4dad932e532eb6551e0ea02"
          }
        ]
      },
      tickets_mark: nil,
      offenders_mark: nil,
      author_index: 2,
      entropy_source:
        "0x8fc34b4c24f74f16ef7b13fff47ab7b84e6ce6ccae23870ee63d0b9c39261eb84dfed75e12c38d7599bf39f443f5fa5ce583a10b96d1184b450752a93c8c6a1566a41c9aa8ac0645aef85b6f6c0c6c00bc7421cd472cac7011abc190116e8b0d",
      seal:
        "0xc0909e69767bdce7476a497eabc11c3ab0892703755c7ed244c8144424fa3971f6d91686fc3c8d2cf53a86fa4ca45198003982bdd0667731f5f45309453548187276557f5c79907216a4397b2bce42420546e96ea1da5dc5b27ea41478cb3902"
    }

    header = Header.from_json(h)

    expected_hex =
      "000000000000000000000000000000000000000000000000000000000000000068d749b661c2a6414324a3b0e8dc53791f9c6da964b465d9745f7da819eb4592dc080ad182cb9ff052a1ca8ecbc51164264efc7dd6debaaa45764950f843acb8b46f4b00016f6ad2224d7d58aec6573c623ab110700eaca20a48dc2965d535e466d524af2a835ac82bfa2ce8390bb50680d4b7a73dfa2a4cff6d8c30694b24a605f9574eaf5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da293d5e5a51aab2b048f8686ecd79712a80e3265a114cc73f14bdb2a59233fb66d022351e22105a19aabb42589162ad7f1ea0df1c25cebf0e4a9fcd261301274862aa2b95f7572875b0d0f186552ae745ba8222fc0b5bd456554bfe51c68938f8bce68e0cf7f26c59f963b5846202d2327cc8bc0c4eff8cb9abd4012f9a71decf007f6190116d118d643a98878e294ccf62b509e214299931aad8ff9764181a4e33b3e0e096b02e2ec98a3441410aeddd78c95e27a0da6f411a09c631c0f2bea6e948e5fcdce10e0b64ec4eebd0d9211c7bac2f27ce54bca6f7776ff6fee86ab3e35c7f34a4bd4f2d04076a8c6f9060a0c8d2c6bdd082ceb3eda7df381cb260fafff16e5352840afb47e206b5c89f560f2611835855cf2e6ebad1acc9520a72591d837ce344bc9defceb0d7de7e9e9925096768b7adb4dad932e532eb6551e0ea02000002008fc34b4c24f74f16ef7b13fff47ab7b84e6ce6ccae23870ee63d0b9c39261eb84dfed75e12c38d7599bf39f443f5fa5ce583a10b96d1184b450752a93c8c6a1566a41c9aa8ac0645aef85b6f6c0c6c00bc7421cd472cac7011abc190116e8b0d"

    {:ok, bin} = Base.decode16(expected_hex, case: :lower)

    assert Header.unsigned_encode(header) == bin
  end
end
