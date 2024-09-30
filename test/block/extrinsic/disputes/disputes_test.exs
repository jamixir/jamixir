defmodule Block.Extrinsic.Disputes.Test do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes
  alias System.State.Judgements
  alias Util.Time
  import Jamixir.Factory

  setup_all do
    {current_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    {prev_pub, _} = :crypto.generate_key(:eddsa, :ed25519)

    state = %{
      build(:genesis_state)
      | curr_validators: [build(:validator, ed25519: current_pub)],
        prev_validators: [build(:validator, ed25519: prev_pub)],
        judgements: %Judgements{}
    }

    {:ok, work_report_hash: :crypto.strong_rand_bytes(32), state: state, header: build(:header)}
  end

  defp validate(disputes, state, header) do
    Disputes.validate(
      disputes,
      state.curr_validators,
      state.prev_validators,
      state.judgements,
      header.timeslot
    )
  end

  describe "validate/3 error cases" do
    test "returns errors for invalid verdicts", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      error_cases = [
        {
          "Invalid epoch index in verdicts",
          %Disputes{verdicts: [build(:verdict, epoch_index: 100)]}
        },
        {
          "Invalid number of judgements in verdicts",
          %Disputes{verdicts: [build(:verdict, judgements: [])]}
        },
        {
          "Invalid order or duplicates in verdict work report hashes",
          %Disputes{
            verdicts: [
              build(:verdict, work_report_hash: wrh),
              build(:verdict, work_report_hash: wrh)
            ]
          }
        },
        {
          "Invalid order or duplicates in verdict work report hashes",
          %Disputes{
            verdicts: [
              build(:verdict, work_report_hash: <<0xCC::256>>),
              build(:verdict, work_report_hash: <<0xBB::256>>),
              build(:verdict, work_report_hash: <<0xAA::256>>)
            ]
          }
        },
        {
          "Work report hashes already exist in current judgments",
          %Disputes{verdicts: [build(:verdict, work_report_hash: wrh)]},
          fn state ->
            %{state | judgements: %{state.judgements | good: MapSet.new([wrh])}}
          end
        },
        {
          "Invalid signatures in verdicts",
          %Disputes{
            verdicts: [
              build(:verdict,
                work_report_hash: wrh,
                judgements: [build(:judgement, signature: <<1::512>>)]
              )
            ]
          }
        }
      ]

      Enum.each(error_cases, fn
        {expected_error, disputes, state_modifier} when is_function(state_modifier) ->
          modified_state = state_modifier.(state)
          assert {:error, ^expected_error} = validate(disputes, modified_state, header)

        {expected_error, disputes} ->
          assert {:error, ^expected_error} = validate(disputes, state, header)
      end)
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
               validate(
                 disputes,
                 state,
                 header
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
               validate(
                 %Disputes{
                   verdicts: [build(:verdict, work_report_hash: wrh, judgements: judgements)]
                 },
                 state,
                 header
               )
    end
  end

  describe "validate/3 error cases for culprits and faults" do
    test "returns errors for invalid culprits and faults", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      state = %{state | curr_validators: [build(:validator, ed25519: pub)]}

      error_cases = [
        {
          "Invalid order or duplicates in culprits Ed25519 keys",
          %Disputes{
            culprits: [
              %{build(:culprit) | work_report_hash: wrh, validator_key: <<2::256>>},
              %{build(:culprit) | work_report_hash: wrh, validator_key: <<2::256>>}
            ]
          }
        },
        {
          "Invalid order or duplicates in culprits Ed25519 keys",
          %Disputes{
            culprits: [
              %{build(:culprit) | work_report_hash: wrh, validator_key: <<2::256>>},
              %{build(:culprit) | work_report_hash: wrh, validator_key: <<1::256>>}
            ]
          }
        },
        {
          "Work report hash in culprits not in the posterior bad set",
          %Disputes{
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
        },
        {
          "culprits reported for a validator not in the allowed validator keys",
          %Disputes{
            verdicts: [
              build(:verdict,
                work_report_hash: wrh,
                judgements: [
                  build(:judgement, decision: false, key_pair: {pub, priv}, work_report_hash: wrh)
                ]
              )
            ],
            culprits: [
              build(:culprit,
                work_report_hash: wrh,
                key_pair: :crypto.generate_key(:eddsa, :ed25519)
              )
            ]
          }
        },
        {
          "Invalid signature in culprits",
          %Disputes{
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
        }
      ]

      Enum.each(error_cases, fn {expected_error, disputes} ->
        assert {:error, ^expected_error} = validate(disputes, state, header)
      end)
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

      disputes = %Disputes{
        verdicts: [
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
        ],
        culprits: [
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {punished_pub, punished_priv}
          )
        ]
      }

      assert {:error, "culprits reported for a validator not in the allowed validator keys"} =
               validate(disputes, state, header)
    end
  end

  describe "validate/3 valid cases" do
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
               validate(
                 %Disputes{culprits: [culprit]},
                 state,
                 header
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
               validate(
                 disputes,
                 state,
                 header
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
               validate(
                 %Disputes{verdicts: [verdict]},
                 state,
                 header
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
               validate(
                 %Disputes{
                   culprits: [
                     build(:culprit,
                       work_report_hash: wrh,
                       key_pair: {pub, priv}
                     )
                   ]
                 },
                 state,
                 header
               )
    end

    test "returns :ok for valid disputes with faults (jam_valid)", %{
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
        faults: [
          build(:fault,
            work_report_hash: wrh,
            key_pair: {pub, priv},
            # This should use SigningContexts.jam_valid()
            decision: true
          )
        ]
      }

      assert :ok ==
               validate(
                 disputes,
                 state,
                 header
               )
    end

    test "returns :ok for valid disputes with faults (jam_invalid)", %{
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
        faults: [
          build(:fault,
            work_report_hash: wrh,
            key_pair: {pub, priv},
            # This should use SigningContexts.jam_invalid()
            decision: false
          )
        ]
      }

      assert :ok ==
               validate(
                 disputes,
                 state,
                 header
               )
    end

    test "returns :ok for valid disputes with verdict from previous epoch", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {curr_pub, _curr_priv} = :crypto.generate_key(:eddsa, :ed25519)
      {prev_pub, prev_priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [build(:validator, ed25519: curr_pub)],
          prev_validators: [build(:validator, ed25519: prev_pub)]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                decision: false,
                key_pair: {prev_pub, prev_priv},
                work_report_hash: wrh,
                validator_index: 0
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot) - 1
          )
        ]
      }

      assert :ok ==
               validate(
                 disputes,
                 state,
                 header
               )
    end
  end
end
