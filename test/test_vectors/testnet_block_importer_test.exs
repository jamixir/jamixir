defmodule TestnetBlockImporterTest do
  alias Util.Export
  alias Block.Header
  alias Codec.State.Json
  alias IO.ANSI
  alias System.State
  import TestVectorUtil
  import Jamixir.Factory
  use ExUnit.Case
  require Logger

  @ignore_fields []
  @genesis_path "state_snapshots"
  @user "javajamio"
  @repo "javajam-trace"

  def state_path(mode), do: "state_snapshots"
  def blocks_path(mode), do: "blocks"

  describe "blocks and states" do
    setup do
      # put parent header to storage
      Storage.put(
        <<0x476243AD7CC4FC49CB6CB362C6568E931731D8650D917007A6037CCEEDD62244::256>>,
        build(:header, timeslot: 0)
      )

      {:ok, genesis_json} = fetch_and_parse_json("0.json", @genesis_path, @user, @repo)
      state = Json.decode(genesis_json)
      {:ok, genesis_state: state}
    end

    # waiting for correctnes of other party side

    skip = ["assurances"]

    for mode <- ["fallback", "safrole", "assurances"] do
      if Enum.member?(skip, mode) do
        IO.puts(
          IO.ANSI.yellow() <>
            "⚠️  Warning: #{mode} mode block import test is disabled" <> IO.ANSI.reset()
        )

        @tag :skip
      end

      @tag mode: mode
      test "#{mode} mode block import", %{genesis_state: state, mode: mode} do
        Enum.reduce([""], state, fn epoch, state ->
          Enum.reduce(6_008_213..6_008_237, state, fn timeslot, state ->
            Logger.info("🧱 Processing block #{epoch}:#{timeslot}")
            # timeslot = String.pad_leading("#{timeslot}", 3, "0")

            block_bin = fetch_binary("#{epoch}#{timeslot}.bin", blocks_path(mode), @user, @repo)

            {block, _} = Block.decode(block_bin)
            Export.export(state, "priv/")

            {:ok, json} =
              fetch_and_parse_json("#{epoch}#{timeslot}.json", state_path(mode), @user, @repo)

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
          "0x5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d",
          "0x3d5e5a51aab2b048f8686ecd79712a80e3265a114cc73f14bdb2a59233fb66d0",
          "0xaa2b95f7572875b0d0f186552ae745ba8222fc0b5bd456554bfe51c68938f8bc",
          "0x7f6190116d118d643a98878e294ccf62b509e214299931aad8ff9764181a4e33",
          "0x48e5fcdce10e0b64ec4eebd0d9211c7bac2f27ce54bca6f7776ff6fee86ab3e3",
          "0xf16e5352840afb47e206b5c89f560f2611835855cf2e6ebad1acc9520a72591d"
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
      "000000000000000000000000000000000000000000000000000000000000000068d749b661c2a6414324a3b0e8dc53791f9c6da964b465d9745f7da819eb4592dc080ad182cb9ff052a1ca8ecbc51164264efc7dd6debaaa45764950f843acb8b46f4b00016f6ad2224d7d58aec6573c623ab110700eaca20a48dc2965d535e466d524af2a835ac82bfa2ce8390bb50680d4b7a73dfa2a4cff6d8c30694b24a605f9574eaf5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d3d5e5a51aab2b048f8686ecd79712a80e3265a114cc73f14bdb2a59233fb66d0aa2b95f7572875b0d0f186552ae745ba8222fc0b5bd456554bfe51c68938f8bc7f6190116d118d643a98878e294ccf62b509e214299931aad8ff9764181a4e3348e5fcdce10e0b64ec4eebd0d9211c7bac2f27ce54bca6f7776ff6fee86ab3e3f16e5352840afb47e206b5c89f560f2611835855cf2e6ebad1acc9520a72591d000002008fc34b4c24f74f16ef7b13fff47ab7b84e6ce6ccae23870ee63d0b9c39261eb84dfed75e12c38d7599bf39f443f5fa5ce583a10b96d1184b450752a93c8c6a1566a41c9aa8ac0645aef85b6f6c0c6c00bc7421cd472cac7011abc190116e8b0d"

    {:ok, bin} = Base.decode16(expected_hex, case: :lower)

    assert Header.unsigned_encode(header) == bin
  end
end
