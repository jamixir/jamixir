defmodule System.StateTransition.JudgementsTest do
  use ExUnit.Case
  import Jamixir.Factory

  alias System.State
  alias Block.{Header, Extrinsic}
  alias Block.Extrinsic.Disputes
  alias Block.Extrinsic.Disputes.{Verdict, Culprit, Fault, Judgement}
  alias System.State.{Validator, Judgements}

  setup do
    %{state: state, validators: validators, key_pairs: key_pairs} =
      build(:genesis_state_with_safrole, validator_count: 1)

    work_report_hash = <<0xAAC4C749F1D5EC07BF0502C8072E95033D48E31B1B9DFDCB8D42BD80445F713E::256>>

    valid_key_private =
      <<0x935D5AEF2E41122B21A6590B079352130CAEE5EA80B3D9E3B8D7C2E884D64B58::256>>

    {valid_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, valid_key_private)
    valid_signature = :crypto.sign(:eddsa, :none, work_report_hash, [valid_key_private, :ed25519])

    prev_key_private = <<0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0::256>>
    {prev_key_public, _} = :crypto.generate_key(:eddsa, :ed25519, prev_key_private)

    valid_judgement = %Judgement{validator_index: 0, decision: true, signature: valid_signature}

    valid_offense = %Culprit{
      work_report_hash: work_report_hash,
      validator_key: valid_key_public,
      signature: valid_signature
    }

    state = %System.State{
      state
      | curr_validators:
          List.replace_at(validators, 0, %Validator{
            Enum.at(validators, 0)
            | ed25519: valid_key_public
          }),
        prev_validators:
          List.replace_at(validators, 0, %Validator{
            Enum.at(validators, 0)
            | ed25519: prev_key_public
          }),
        judgements: %Judgements{},
        timeslot: 600
    }

    header =
      System.HeaderSeal.seal_header(
        %Header{timeslot: 601, block_author_key_index: rem(601, length(validators))},
        state.safrole.current_epoch_slot_sealers,
        state.entropy_pool,
        Enum.at(key_pairs, rem(601, length(validators)))
      )

    {:ok,
     state: state,
     header: header,
     work_report_hash: work_report_hash,
     valid_judgement: valid_judgement,
     valid_offense: valid_offense,
     valid_key_private: valid_key_private,
     valid_key_public: valid_key_public,
     key_pairs: key_pairs}
  end

  test "adds to good set", %{
    state: state,
    header: header,
    work_report_hash: work_report_hash,
    valid_judgement: valid_judgement
  } do
    verdict = %Verdict{
      work_report_hash: work_report_hash,
      epoch_index: 1,
      judgements:
        Enum.map(1..length(state.curr_validators), fn i ->
          %Judgement{valid_judgement | validator_index: i - 1, decision: true}
        end)
    }

    block = %Block{
      header: header,
      extrinsic: %Extrinsic{disputes: %Disputes{verdicts: [verdict], culprits: [], faults: []}}
    }

    assert MapSet.member?(State.add_block(state, block).judgements.good, work_report_hash)
  end

  test "adds to wonky set", %{
    state: state,
    header: header,
    work_report_hash: work_report_hash,
    valid_judgement: valid_judgement
  } do
    state = %{
      state
      | curr_validators:
          Enum.map(1..3, fn i ->
            %{
              Enum.at(state.curr_validators, 0)
              | ed25519:
                  Enum.at(state.curr_validators, rem(i, length(state.curr_validators))).ed25519
            }
          end)
    }

    wonky_votes =
      Enum.map(1..3, fn i ->
        %Judgement{valid_judgement | validator_index: i - 1, decision: i == 2}
      end)

    block = %Block{
      header: header,
      extrinsic: %Extrinsic{
        disputes: %Disputes{
          verdicts: [
            %Verdict{work_report_hash: work_report_hash, epoch_index: 1, judgements: wonky_votes}
          ],
          culprits: [],
          faults: []
        }
      }
    }

    assert MapSet.member?(State.add_block(state, block).judgements.wonky, work_report_hash)
  end

  test "updates state with valid disputes", %{
    state: state,
    header: header,
    work_report_hash: work_report_hash,
    valid_judgement: valid_judgement,
    valid_offense: valid_offense
  } do
    block = %{
      build(:block)
      | header: header,
        extrinsic: %Extrinsic{
          disputes: %Disputes{
            verdicts: [
              %Verdict{
                work_report_hash: work_report_hash,
                epoch_index: 1,
                judgements: [%Judgement{valid_judgement | decision: false}]
              }
            ],
            culprits: [valid_offense],
            faults: []
          }
        }
    }

    new_state = State.add_block(state, block)
    assert MapSet.member?(new_state.judgements.bad, work_report_hash)
    assert MapSet.member?(new_state.judgements.punish, valid_offense.validator_key)
  end

  test "filters out duplicate work report hashes", %{
    state: state,
    header: header,
    work_report_hash: work_report_hash,
    valid_judgement: valid_judgement,
    valid_offense: valid_offense
  } do
    state = %{state | judgements: %Judgements{bad: MapSet.new([work_report_hash])}}

    block = %Block{
      header: header,
      extrinsic: %Extrinsic{
        disputes: %Disputes{
          verdicts: [
            %Verdict{
              work_report_hash: work_report_hash,
              epoch_index: 1,
              judgements: [%Judgement{valid_judgement | decision: false}]
            }
          ],
          culprits: [valid_offense],
          faults: []
        }
      }
    }

    new_state = State.add_block(state, block)
    assert MapSet.member?(new_state.judgements.bad, work_report_hash)
    refute MapSet.member?(new_state.judgements.good, work_report_hash)
    refute MapSet.member?(new_state.judgements.wonky, work_report_hash)
  end

  test "updates punish set with valid offenses", %{
    state: state,
    header: header,
    valid_key_private: valid_key_private,
    valid_key_public: valid_key_public
  } do
    valid_signature_1 = :crypto.sign(:eddsa, :none, <<1::256>>, [valid_key_private, :ed25519])
    valid_signature_2 = :crypto.sign(:eddsa, :none, <<2::256>>, [valid_key_private, :ed25519])

    state = %{
      state
      | curr_validators:
          List.replace_at(state.curr_validators, 0, %Validator{
            Enum.at(state.curr_validators, 0)
            | ed25519: valid_key_public
          }),
        judgements: %Judgements{bad: MapSet.new([<<1::256>>, <<2::256>>])}
    }

    block = %Block{
      header: header,
      extrinsic: %Extrinsic{
        disputes: %Disputes{
          verdicts: [],
          culprits: [
            %Culprit{
              work_report_hash: <<1::256>>,
              validator_key: valid_key_public,
              signature: valid_signature_1
            }
          ],
          faults: []
        }
      }
    }

    new_state = State.add_block(state, block)
    assert MapSet.member?(new_state.judgements.bad, <<1::256>>)
    assert MapSet.member?(new_state.judgements.punish, valid_key_public)
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
