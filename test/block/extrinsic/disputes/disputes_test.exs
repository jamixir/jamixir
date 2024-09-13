defmodule Block.Extrinsic.Disputes.Test do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes
  alias System.State.{Judgements}
  alias Util.{Time}
  import Jamixir.Factory

  setup do
    {current_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    {prev_pub, _} = :crypto.generate_key(:eddsa, :ed25519)

    current_validator = build(:validator, ed25519: current_pub)
    previous_validator = build(:validator, ed25519: prev_pub)

    state = %{
      build(:genesis_state)
      | curr_validators: [current_validator],
        prev_validators: [previous_validator],
        judgements: %Judgements{}
    }

    work_report_hash = :crypto.strong_rand_bytes(32)
    header = build(:header)

    {:ok, work_report_hash: work_report_hash, state: state, header: header}
  end

  describe "validate_disputes/3 error cases" do
    test "returns error for invalid epoch index", %{state: state, header: header} do
      assert {:error, "Invalid epoch index in verdicts"} =
               Disputes.validate_disputes(
                 %Disputes{verdicts: [build(:verdict, epoch_index: 100)]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for invalid number of judgements", %{
      state: state,
      header: header
    } do
      assert {:error, "Invalid number of judgements in verdicts"} =
               Disputes.validate_disputes(
                 %Disputes{verdicts: [build(:verdict, judgements: [])]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for non-unique work report hashes", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      assert {:error, "Invalid order or duplicates in verdict work report hashes"} =
               Disputes.validate_disputes(
                 %Disputes{
                   verdicts: [
                     build(:verdict, work_report_hash: wrh),
                     build(:verdict, work_report_hash: wrh)
                   ]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for incorrectly ordered work report hashes", %{
      state: state,
      header: header
    } do
      assert {:error, "Invalid order or duplicates in verdict work report hashes"} =
               Disputes.validate_disputes(
                 %Disputes{
                   verdicts: [
                     build(:verdict, work_report_hash: <<0xCC::256>>),
                     build(:verdict, work_report_hash: <<0xBB::256>>),
                     build(:verdict, work_report_hash: <<0xAA::256>>)
                   ]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for work report hashes already in judgements", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      state = %{state | judgements: %{state.judgements | good: MapSet.new([wrh])}}

      assert {:error, "Work report hashes already exist in current judgments"} =
               Disputes.validate_disputes(
                 %Disputes{verdicts: [build(:verdict, work_report_hash: wrh)]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for invalid signatures", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      assert {:error, "Invalid signatures in verdicts"} =
               Disputes.validate_disputes(
                 %Disputes{
                   verdicts: [
                     build(:verdict,
                       work_report_hash: wrh,
                       judgements: [build(:judgement, signature: <<1::512>>)]
                     )
                   ]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for non-ordered validator indices", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      key_pairs =
        for _ <- 1..3 do
          :crypto.generate_key(:eddsa, :ed25519)
        end

      state = %{
        state
        | curr_validators:
            Enum.map(key_pairs, fn {pub, _priv} ->
              %{build(:validator) | ed25519: pub}
            end)
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                validator_index: 1,
                key_pair: Enum.at(key_pairs, 1),
                work_report_hash: wrh
              ),
              build(:judgement,
                validator_index: 0,
                key_pair: Enum.at(key_pairs, 0),
                work_report_hash: wrh
              ),
              build(:judgement,
                validator_index: 2,
                key_pair: Enum.at(key_pairs, 2),
                work_report_hash: wrh
              )
            ]
          )
        ]
      }

      assert {:error, "Judgements not ordered by validator index or contain duplicates"} =
               Disputes.validate_disputes(
                 disputes,
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for invalid sum of judgements", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      key_pairs = for _ <- 1..5, do: :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: Enum.map(key_pairs, fn {pub, _} -> build(:validator, ed25519: pub) end)
      }

      judgements = [
        build(:judgement,
          decision: true,
          key_pair: Enum.at(key_pairs, 0),
          work_report_hash: wrh,
          validator_index: 0
        ),
        build(:judgement,
          decision: true,
          key_pair: Enum.at(key_pairs, 1),
          work_report_hash: wrh,
          validator_index: 1
        ),
        build(:judgement,
          decision: false,
          key_pair: Enum.at(key_pairs, 2),
          work_report_hash: wrh,
          validator_index: 2
        ),
        build(:judgement,
          decision: false,
          key_pair: Enum.at(key_pairs, 3),
          work_report_hash: wrh,
          validator_index: 3
        )
      ]

      assert {:error, "Invalid sum of judgements in verdicts"} =
               Disputes.validate_disputes(
                 %Disputes{
                   verdicts: [build(:verdict, work_report_hash: wrh, judgements: judgements)]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for duplicate validator keys in cuplrits", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      assert {:error, "Invalid order or duplicates in culprits Ed25519 keys"} =
               Disputes.validate_disputes(
                 %Disputes{
                   culprits: [
                     %{build(:culprit) | work_report_hash: wrh, validator_key: <<2::256>>},
                     %{build(:culprit) | work_report_hash: wrh, validator_key: <<2::256>>}
                   ]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for non ordered validator keys in cuplrits", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      assert {:error, "Invalid order or duplicates in culprits Ed25519 keys"} =
               Disputes.validate_disputes(
                 %Disputes{
                   culprits: [
                     %{build(:culprit) | work_report_hash: wrh, validator_key: <<2::256>>},
                     %{build(:culprit) | work_report_hash: wrh, validator_key: <<1::256>>}
                   ]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for culprit work report hash not in bad set", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [build(:validator, ed25519: pub)]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement, decision: true, key_pair: {pub, priv}, work_report_hash: wrh)
            ]
          )
        ],
        culprits: [build(:culprit, work_report_hash: wrh, key_pair: {pub, priv})]
      }

      assert {:error, "Work report hash in culprits not in the posterior bad set"} =
               Disputes.validate_disputes(
                 disputes,
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for invalid culprit validator key", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {valid_pub, valid_priv} = :crypto.generate_key(:eddsa, :ed25519)
      {invalid_pub, invalid_priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{state | curr_validators: [build(:validator, ed25519: valid_pub)]}

      verdict =
        build(:verdict,
          work_report_hash: wrh,
          judgements: [
            build(:judgement,
              decision: false,
              key_pair: {valid_pub, valid_priv},
              work_report_hash: wrh
            )
          ]
        )

      culprit =
        build(:culprit,
          work_report_hash: wrh,
          key_pair: {invalid_pub, invalid_priv}
        )

      assert {:error, "culprits reported for a validator not in the allowed validator keys"} =
               Disputes.validate_disputes(
                 %Disputes{verdicts: [verdict], culprits: [culprit]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for culprit validator key in punish set", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {punished_pub, punished_priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [
            build(:validator, ed25519: punished_pub)
          ],
          judgements: %{state.judgements | punish: MapSet.new([punished_pub])}
      }

      verdict =
        build(:verdict,
          work_report_hash: wrh,
          judgements: [
            build(:judgement,
              decision: false,
              key_pair: {punished_pub, punished_priv},
              work_report_hash: wrh
            )
          ]
        )

      culprit =
        build(:culprit,
          work_report_hash: wrh,
          key_pair: {punished_pub, punished_priv}
        )

      assert {:error, "culprits reported for a validator not in the allowed validator keys"} =
               Disputes.validate_disputes(
                 %Disputes{verdicts: [verdict], culprits: [culprit]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns error for invalid culprit signature", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      state = %{state | curr_validators: [build(:validator, ed25519: pub)]}

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement, decision: false, key_pair: {pub, priv}, work_report_hash: wrh)
            ]
          )
        ],
        culprits: [
          %{
            build(:culprit,
              work_report_hash: wrh,
              key_pair: {pub, priv}
            )
            | signature: <<1::512>>
          }
        ]
      }

      assert {:error, "Invalid signature in culprits"} =
               Disputes.validate_disputes(
                 disputes,
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end
  end

  describe "validate_disputes/3 valid cases" do
    test "returns :ok for valid disputes with bad set from state judgements", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [build(:validator, ed25519: pub)],
          judgements: %{state.judgements | bad: MapSet.new([wrh])}
      }

      culprit =
        build(:culprit,
          work_report_hash: wrh,
          key_pair: {pub, priv}
        )

      assert :ok ==
               Disputes.validate_disputes(
                 %Disputes{culprits: [culprit]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns :ok for valid disputes with bad set from new verdicts", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [build(:validator, ed25519: pub)]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                decision: false,
                key_pair: {pub, priv},
                work_report_hash: wrh
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ],
        culprits: [
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {pub, priv}
          )
        ]
      }

      assert :ok ==
               Disputes.validate_disputes(
                 disputes,
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns :ok for valid disputes with only verdicts", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      key_pairs = for _ <- 1..3, do: :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: Enum.map(key_pairs, fn {pub, _} -> build(:validator, ed25519: pub) end)
      }

      judgements = [
        build(:judgement,
          decision: false,
          key_pair: Enum.at(key_pairs, 0),
          work_report_hash: wrh,
          validator_index: 0
        ),
        build(:judgement,
          decision: false,
          key_pair: Enum.at(key_pairs, 1),
          work_report_hash: wrh,
          validator_index: 1
        ),
        build(:judgement,
          decision: true,
          key_pair: Enum.at(key_pairs, 2),
          work_report_hash: wrh,
          validator_index: 2
        )
      ]

      verdict =
        build(:verdict,
          work_report_hash: wrh,
          judgements: judgements,
          epoch_index: Time.epoch_index(header.timeslot)
        )

      assert :ok ==
               Disputes.validate_disputes(
                 %Disputes{verdicts: [verdict]},
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end

    test "returns :ok for valid disputes with only culprits", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [build(:validator, ed25519: pub)],
          judgements: %{state.judgements | bad: MapSet.new([wrh])}
      }

      assert :ok ==
               Disputes.validate_disputes(
                 %Disputes{
                   culprits: [
                     build(:culprit,
                       work_report_hash: wrh,
                       key_pair: {pub, priv}
                     )
                   ]
                 },
                 state.curr_validators,
                 state.prev_validators,
                 state.judgements,
                 header.timeslot
               )
    end
  end
end
