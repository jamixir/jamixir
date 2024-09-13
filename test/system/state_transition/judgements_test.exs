defmodule System.State.JudgementsTest do
  use ExUnit.Case
  alias System.State.Judgements
  alias Block.Extrinsic.Disputes
  alias Util.Time
  import Jamixir.Factory

  defp assert_updated_set(result, state, set_key, new_item) do
    assert MapSet.member?(Map.get(result, set_key), new_item)
    assert MapSet.subset?(Map.get(state.judgements, set_key), Map.get(result, set_key))

    for key <- [:good, :bad, :wonky, :punish] -- [set_key] do
      assert Map.get(result, key) == Map.get(state.judgements, key)
    end
  end

  setup_all do
    {current_pub, current_priv} = :crypto.generate_key(:eddsa, :ed25519)
    {prev_pub, prev_priv} = :crypto.generate_key(:eddsa, :ed25519)

    current_validator = build(:validator, ed25519: current_pub)
    previous_validator = build(:validator, ed25519: prev_pub)

    state = %{
      build(:genesis_state)
      | curr_validators: [current_validator],
        prev_validators: [previous_validator],
        judgements: build(:judgements)
    }

    work_report_hash = :crypto.strong_rand_bytes(32)
    header = build(:header)

    {:ok,
     work_report_hash: work_report_hash,
     state: state,
     header: header,
     current_key: {current_pub, current_priv},
     prev_key: {prev_pub, prev_priv}}
  end

  describe "posterior_judgements/3" do
    test "returns unchanged judgements on validation error", %{state: state, header: header} do
      assert Judgements.posterior_judgements(header, %Disputes{}, state) == state.judgements
    end

    test "returns unchanged judgements for invalid epoch index", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      current_key: key_pair
    } do
      result =
        Judgements.posterior_judgements(
          header,
          %Disputes{
            verdicts: [
              build(:verdict,
                work_report_hash: wrh,
                judgements: [build(:judgement, work_report_hash: wrh, key_pair: key_pair)],
                epoch_index: Time.epoch_index(header.timeslot) + 2
              )
            ]
          },
          state
        )

      assert result == state.judgements
    end

    test "updates good set correctly", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      current_key: key_pair
    } do
      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [build(:judgement, work_report_hash: wrh, key_pair: key_pair)],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ]
      }

      result = Judgements.posterior_judgements(header, disputes, state)
      assert_updated_set(result, state, :good, wrh)
    end

    test "updates bad set correctly", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      current_key: key_pair
    } do
      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement, decision: false, work_report_hash: wrh, key_pair: key_pair)
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ]
      }

      result = Judgements.posterior_judgements(header, disputes, state)
      assert_updated_set(result, state, :bad, wrh)
    end

    test "updates wonky set correctly", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      current_key: key_pair
    } do
      {pub1, priv1} = :crypto.generate_key(:eddsa, :ed25519)
      {pub2, priv2} = :crypto.generate_key(:eddsa, :ed25519)

      state =
        update_in(
          state.curr_validators,
          &(&1 ++ [build(:validator, ed25519: pub1), build(:validator, ed25519: pub2)])
        )

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              %{
                build(:judgement, work_report_hash: wrh, key_pair: key_pair)
                | validator_index: 0
              },
              %{
                build(:judgement, work_report_hash: wrh, decision: false, key_pair: {pub1, priv1})
                | validator_index: 1
              },
              %{
                build(:judgement, work_report_hash: wrh, decision: false, key_pair: {pub2, priv2})
                | validator_index: 2
              }
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ]
      }

      result = Judgements.posterior_judgements(header, disputes, state)
      assert_updated_set(result, state, :wonky, wrh)
    end

    test "updates punish set correctly", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      current_key: key_pair
    } do
      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                decision: false,
                work_report_hash: wrh,
                key_pair: key_pair
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ],
        culprits: [build(:culprit, work_report_hash: wrh, key_pair: key_pair)]
      }

      result = Judgements.posterior_judgements(header, disputes, state)
      {pub, _} = key_pair
      assert MapSet.member?(result.bad, wrh)
      assert MapSet.member?(result.punish, pub)
      assert result.good == state.judgements.good
      assert result.wonky == state.judgements.wonky
    end
  end

  describe "encode/1" do
    test "judgements encoding smoke test" do
      assert Codec.Encoder.encode(%Judgements{
               good: MapSet.new([<<1>>, <<2>>]),
               bad: MapSet.new([<<2>>]),
               wonky: MapSet.new([<<3>>]),
               punish: MapSet.new([<<4>>])
             }) == <<2, 1, 2, 1, 2, 1, 3, 1, 4>>
    end
  end
end
