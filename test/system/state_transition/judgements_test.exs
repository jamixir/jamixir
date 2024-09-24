defmodule System.State.JudgementsTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Disputes
  alias System.State.Judgements
  alias Util.Time
  import Mox
  setup :verify_on_exit!

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

    {:ok,
     work_report_hash: :crypto.strong_rand_bytes(32),
     state: state,
     header: build(:header),
     current_key: {current_pub, current_priv},
     prev_key: {prev_pub, prev_priv}}
  end

  describe "header validation" do
    test "passes when validation succeeds", %{state: state, work_report_hash: wrh, header: header} do
      assert {:ok, _, _} =
               Judgements.posterior_judgements(
                 %{header | judgements_marker: [wrh], offenders_marker: []},
                 %Disputes{
                   verdicts: [build(:verdict, work_report_hash: wrh, judgements: [])],
                   culprits: [],
                   faults: []
                 },
                 state
               )
    end

    test "fails because of verdicts mismatch", %{
      state: state,
      work_report_hash: wrh,
      header: header
    } do
      assert {:error, "Header validation failed"} =
               Judgements.posterior_judgements(
                 %{header | judgements_marker: [], offenders_marker: []},
                 %Disputes{
                   verdicts: [build(:verdict, work_report_hash: wrh, judgements: [])],
                   culprits: [],
                   faults: []
                 },
                 state
               )
    end

    test "fails because of offenders mismatch", %{
      state: state,
      current_key: {pub, _},
      header: header
    } do
      assert {:error, "Header validation failed"} =
               Judgements.posterior_judgements(
                 %{header | judgements_marker: [], offenders_marker: []},
                 %Disputes{
                   verdicts: [],
                   culprits: [build(:culprit, validator_key: pub)],
                   faults: []
                 },
                 state
               )
    end

    test "fails because of order mismatch", %{state: state, work_report_hash: wrh, header: header} do
      wrh2 = :crypto.strong_rand_bytes(32)

      assert {:error, "Header validation failed"} =
               Judgements.posterior_judgements(
                 %{header | judgements_marker: [wrh2, wrh], offenders_marker: []},
                 %Disputes{
                   verdicts: [
                     build(:verdict, work_report_hash: wrh, judgements: []),
                     build(:verdict, work_report_hash: wrh2, judgements: [])
                   ],
                   culprits: [],
                   faults: []
                 },
                 state
               )
    end
  end

  describe "posterior_judgements/3" do
    setup do
      # Exclude posterior_judgements from being mocked
      Application.put_env(:jamixir, :original_modules, [:posterior_judgements])

      on_exit(fn ->
        Application.delete_env(:jamixir, :original_modules)
      end)

      :ok
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

      {:ok, result, _} = Judgements.posterior_judgements(header, disputes, state)
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

      {:ok, result, _} = Judgements.posterior_judgements(header, disputes, state)
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

      {:ok, result, _} = Judgements.posterior_judgements(header, disputes, state)
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

      {:ok, result, _} = Judgements.posterior_judgements(header, disputes, state)
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
