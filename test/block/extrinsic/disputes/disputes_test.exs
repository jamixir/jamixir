defmodule Block.Extrinsic.Disputes.Test do
  use ExUnit.Case
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.Error
  alias System.State.Judgements
  alias Util.{Hash, Time}
  import Jamixir.Factory
  use Sizes
  import Codec.Encoder

  setup_all do
    # Generate and sort key pairs
    key_pairs =
      for _ <- 1..3 do
        :crypto.generate_key(:eddsa, :ed25519)
      end
      |> Enum.sort_by(fn {pub, _priv} -> pub end)

    {current_pub, _} = :crypto.generate_key(:eddsa, :ed25519)
    {prev_pub, _} = :crypto.generate_key(:eddsa, :ed25519)

    state = %{
      build(:genesis_state)
      | curr_validators: [build(:validator, ed25519: current_pub)],
        prev_validators: [build(:validator, ed25519: prev_pub)],
        judgements: %Judgements{}
    }

    {:ok,
     work_report_hash: Hash.random(),
     state: state,
     header: build(:header),
     sorted_key_pairs: key_pairs}
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
          Error.bad_judgement_age(),
          %Disputes{verdicts: [build(:verdict, epoch_index: 100)]}
        },
        {
          Error.bad_vote_split(),
          %Disputes{verdicts: [build(:verdict, judgements: [])]}
        },
        {
          Error.unsorted_verdicts(),
          %Disputes{
            verdicts: [
              build(:verdict, work_report_hash: wrh),
              build(:verdict, work_report_hash: wrh)
            ]
          }
        },
        {
          Error.unsorted_verdicts(),
          %Disputes{
            verdicts: [
              build(:verdict, work_report_hash: <<0xCC::hash()>>),
              build(:verdict, work_report_hash: <<0xBB::hash()>>),
              build(:verdict, work_report_hash: <<0xAA::hash()>>)
            ]
          }
        },
        {
          Error.already_judged(),
          %Disputes{verdicts: [build(:verdict, work_report_hash: wrh)]},
          fn state ->
            %{state | judgements: %{state.judgements | good: MapSet.new([wrh])}}
          end
        },
        {
          Error.invalid_signature(),
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
        | curr_validators: for({pub, _} <- key_pairs, do: build(:validator, ed25519: pub))
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

      expected_error = Error.unsorted_judgements()
      assert {:error, ^expected_error} = validate(disputes, state, header)
    end

    test "returns error for invalid sum of judgements", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      key_pairs = [k1, k2, k3, k4, _] = for _ <- 1..5, do: :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: for({pub, _} <- key_pairs, do: build(:validator, ed25519: pub))
      }

      judgements = [
        build(:judgement, vote: true, key_pair: k1, work_report_hash: wrh, validator_index: 0),
        build(:judgement, vote: true, key_pair: k2, work_report_hash: wrh, validator_index: 1),
        build(:judgement, vote: false, key_pair: k3, work_report_hash: wrh, validator_index: 2),
        build(:judgement, vote: false, key_pair: k4, work_report_hash: wrh, validator_index: 3)
      ]

      expected_error = Error.bad_vote_split()

      assert {:error, ^expected_error} =
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
          Error.unsorted_culprits(),
          %Disputes{
            culprits: [
              %{build(:culprit) | work_report_hash: wrh, key: Hash.two()},
              %{build(:culprit) | work_report_hash: wrh, key: Hash.two()}
            ]
          }
        },
        {
          Error.unsorted_culprits(),
          %Disputes{
            culprits: [
              %{build(:culprit) | work_report_hash: wrh, key: Hash.two()},
              %{build(:culprit) | work_report_hash: wrh, key: Hash.one()}
            ]
          }
        },
        {
          Error.not_enough_faults(),
          %Disputes{
            verdicts: [
              build(:verdict,
                work_report_hash: wrh,
                judgements: [
                  build(:judgement, vote: true, key_pair: {pub, priv}, work_report_hash: wrh)
                ]
              )
            ],
            culprits: [build(:culprit, work_report_hash: wrh, key_pair: {pub, priv})]
          }
        },
        {
          Error.not_enough_culprits(),
          %Disputes{
            verdicts: [
              build(:verdict,
                work_report_hash: wrh,
                judgements: [
                  build(:judgement, vote: false, key_pair: {pub, priv}, work_report_hash: wrh)
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
          Error.not_enough_culprits(),
          %Disputes{
            verdicts: [
              build(:verdict,
                work_report_hash: wrh,
                judgements: [
                  build(:judgement, vote: false, key_pair: {pub, priv}, work_report_hash: wrh)
                ]
              )
            ],
            culprits: [
              %{
                build(:culprit,
                  work_report_hash: wrh,
                  key_pair: {pub, priv}
                )
                | signature: <<1::size(@signature_size * 8)>>
              }
            ]
          }
        }
      ]

      Enum.each(error_cases, fn {expected_error, disputes} ->
        assert {:error, ^expected_error} = validate(disputes, state, header)
      end)
    end

    test "returns error for culprit validator key in offenders set", %{
      state: state,
      header: header,
      work_report_hash: wrh
    } do
      {offendersed_pub, offendersed_priv} = :crypto.generate_key(:eddsa, :ed25519)

      state = %{
        state
        | curr_validators: [
            build(:validator, ed25519: offendersed_pub)
          ],
          judgements: %{state.judgements | offenders: MapSet.new([offendersed_pub])}
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                vote: false,
                key_pair: {offendersed_pub, offendersed_priv},
                work_report_hash: wrh
              )
            ]
          )
        ],
        culprits: [
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {offendersed_pub, offendersed_priv}
          )
        ]
      }

      expected_error = Error.not_enough_culprits()
      assert {:error, ^expected_error} = validate(disputes, state, header)
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
      work_report_hash: wrh,
      sorted_key_pairs: [k1, k2 | _]
    } do
      {pub1, priv1} = k1
      {pub2, priv2} = k2

      state = %{
        state
        | curr_validators: [
            build(:validator, ed25519: pub1),
            build(:validator, ed25519: pub2)
          ]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                vote: false,
                key_pair: {pub1, priv1},
                work_report_hash: wrh,
                validator_index: 0
              ),
              build(:judgement,
                vote: false,
                key_pair: {pub2, priv2},
                work_report_hash: wrh,
                validator_index: 1
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ],
        culprits: [
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {pub1, priv1}
          ),
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {pub2, priv2}
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
        | curr_validators: for({pub, _} <- key_pairs, do: build(:validator, ed25519: pub))
      }

      judgements = [
        build(:judgement,
          vote: false,
          key_pair: Enum.at(key_pairs, 0),
          work_report_hash: wrh,
          validator_index: 0
        ),
        build(:judgement,
          vote: false,
          key_pair: Enum.at(key_pairs, 1),
          work_report_hash: wrh,
          validator_index: 1
        ),
        build(:judgement,
          vote: true,
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

      assert :ok == validate(%Disputes{verdicts: [verdict]}, state, header)
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
      work_report_hash: wrh,
      sorted_key_pairs: [k1, k2 | _]
    } do
      {pub1, priv1} = k1
      {pub2, priv2} = k2

      state = %{
        state
        | curr_validators: [
            build(:validator, ed25519: pub1),
            build(:validator, ed25519: pub2)
          ]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                vote: false,
                key_pair: {pub1, priv1},
                work_report_hash: wrh,
                validator_index: 0
              ),
              build(:judgement,
                vote: false,
                key_pair: {pub2, priv2},
                work_report_hash: wrh,
                validator_index: 1
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ],
        culprits: [
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {pub1, priv1}
          ),
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {pub2, priv2}
          )
        ],
        faults: [
          build(:fault, work_report_hash: wrh, key_pair: {pub1, priv1}, vote: true)
        ]
      }

      assert :ok == validate(disputes, state, header)
    end

    test "returns :ok for valid disputes with faults (jam_invalid)", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      sorted_key_pairs: [k1, k2 | _]
    } do
      {pub1, priv1} = k1
      {pub2, priv2} = k2

      state = %{
        state
        | curr_validators: [
            build(:validator, ed25519: pub1),
            build(:validator, ed25519: pub2)
          ]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                vote: false,
                key_pair: {pub1, priv1},
                work_report_hash: wrh,
                validator_index: 0
              ),
              build(:judgement,
                vote: false,
                key_pair: {pub2, priv2},
                work_report_hash: wrh,
                validator_index: 1
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot)
          )
        ],
        culprits: [
          build(:culprit, work_report_hash: wrh, key_pair: {pub1, priv1}),
          build(:culprit, work_report_hash: wrh, key_pair: {pub2, priv2})
        ],
        faults: [
          build(:fault, work_report_hash: wrh, key_pair: {pub1, priv1}, vote: true),
          build(:fault, work_report_hash: wrh, key_pair: {pub2, priv2}, vote: true)
        ]
      }

      assert :ok == validate(disputes, state, header)
    end

    test "returns :ok for valid disputes with verdict from previous epoch", %{
      state: state,
      header: header,
      work_report_hash: wrh,
      sorted_key_pairs: [k1, k2 | _]
    } do
      {prev_pub1, prev_priv1} = k1
      {prev_pub2, prev_priv2} = k2

      state = %{
        state
        | curr_validators: [
            build(:validator, ed25519: :crypto.generate_key(:eddsa, :ed25519) |> elem(0))
          ],
          prev_validators: [
            build(:validator, ed25519: prev_pub1),
            build(:validator, ed25519: prev_pub2)
          ]
      }

      disputes = %Disputes{
        verdicts: [
          build(:verdict,
            work_report_hash: wrh,
            judgements: [
              build(:judgement,
                vote: false,
                key_pair: {prev_pub1, prev_priv1},
                work_report_hash: wrh,
                validator_index: 0
              ),
              build(:judgement,
                vote: false,
                key_pair: {prev_pub2, prev_priv2},
                work_report_hash: wrh,
                validator_index: 1
              )
            ],
            epoch_index: Time.epoch_index(header.timeslot) - 1
          )
        ],
        culprits: [
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {prev_pub1, prev_priv1}
          ),
          build(:culprit,
            work_report_hash: wrh,
            key_pair: {prev_pub2, prev_priv2}
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

  import TestHelper

  describe "encode / decode" do
    setup_validators(1)

    test "encodes and decodes disputes" do
      disputes = build(:disputes)
      encoded = Codec.Encoder.encode(disputes)
      {decoded, _} = Disputes.decode(encoded)
      assert disputes == decoded
    end
  end
end
