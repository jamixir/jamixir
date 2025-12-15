defmodule Block.Extrinsic.AssuranceTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Assurance
  alias Codec.Encoder
  alias System.State.Validator
  alias Util.{Crypto, Hash}

  setup_all do
    hp = Hash.random()
    keys = for _ <- 1..3, do: :crypto.generate_key(:eddsa, :ed25519)

    validators =
      for {v, i} <- Enum.with_index(build_list(3, :validator)) do
        %Validator{v | ed25519: elem(Enum.at(keys, i), 0)}
      end

    Application.put_env(:jamixir, Constants, AssuranceConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)

    [_, {_, s2}, _] = keys

    assurance =
      build(:assurance,
        hash: hp,
        validator_index: 1,
        bitfield: <<0::344>>
      )
      |> Assurance.signed(s2)

    %{hp: hp, ht: 1, assurance: assurance, validators: validators, core_reports: [], s2: s2}
  end

  describe "Assurance encoding" do
    test "encodes an Assurance struct correctly" do
      assurance = build(:assurance)

      encoded = Encoder.encode(assurance)

      assert encoded ==
               assurance.hash <> assurance.bitfield <> "\x01\0" <> assurance.signature
    end

    test "decodes an Assurance struct correctly" do
      assurance = build(:assurance)

      {decoded, _} = Assurance.decode(Encoder.encode(assurance))
      assert decoded == assurance
    end
  end

  describe "validate_assurances/2" do
    test "returns :ok for valid assurances", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      assurances = [assurance]
      assert :ok == Assurance.validate_assurances(assurances, hp, validators, cr)
    end

    test "returns error when assurance hash doesn't match parent hash", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      d_assurance = %{assurance | hash: Hash.random()}
      assurances = [assurance, d_assurance]

      assert {:error, :bad_attestation_parent} ==
               Assurance.validate_assurances(assurances, hp, validators, cr)
    end

    test "returns error when validator index is out of bounds", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      d_assurance = %{assurance | validator_index: 5_000}
      assurances = [d_assurance]

      assert {:error, :bad_validator_index} ==
               Assurance.validate_assurances(assurances, hp, validators, cr)
    end

    test "returns :ok for empty list of assurances", %{hp: hp, validators: validators} do
      assert :ok == Assurance.validate_assurances([], hp, validators, [])
    end

    test "returns :ok for single valid assurance", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      assert :ok == Assurance.validate_assurances([assurance], hp, validators, cr)
    end

    # Uncomment this test if you implement the validator_index uniqueness check
    test "returns error for duplicate validator indices", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      duplicate_assurance = %{assurance | validator_index: assurance.validator_index}
      assurances = [assurance, duplicate_assurance]

      assert {:error, :duplicates} =
               Assurance.validate_assurances(assurances, hp, validators, cr)
    end

    test "error when validator_index is not ordered", %{
      assurance: assurance,
      hp: hp,
      validators: validators,
      core_reports: cr
    } do
      higher_index = %{assurance | validator_index: assurance.validator_index + 1}

      assert {:error, :not_in_order} ==
               Assurance.validate_assurances([higher_index, assurance], hp, validators, cr)
    end

    test "returns :error for invalid signature assurances", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      invalid_assurance = %{assurance | signature: Crypto.random_sign()}

      assert {:error, :bad_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end

    test "returns :error for invalid validator index", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      invalid_assurance = %{assurance | validator_index: 2}

      assert {:error, :bad_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end

    test "returns :error for invalid bitfield", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      invalid_assurance = %{assurance | bitfield: "other"}

      assert {:error, :bad_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end

    # Formula (11.15) v0.7.2
    test "returns :error when assurance bit is set but core report is null", %{
      hp: hp,
      validators: validators,
      s2: s2
    } do
      invalid_assurance =
        build(:assurance, hash: hp, validator_index: 1, bitfield: <<0::7, 1::1>>)
        |> Assurance.signed(s2)

      assert {:error, :core_not_engaged} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, [nil])
    end

    test "returns :ok when assurance bit is set but core report is not null,and timeslot is not old",
         %{hp: hp, validators: validators, s2: s2} do
      invalid_assurance =
        build(:assurance, hash: hp, validator_index: 1, bitfield: <<1::1, 0::7>>)
        |> Assurance.signed(s2)

      cr = [%{timeslot: 2, core_report: nil}]
      assert :ok == Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end
  end

  describe "assurances_for_new_block/2" do
    setup do
      state = build(:genesis_state)
      {:ok, state: state}
    end

    test "order assurances by validator_index", %{
      state: state,
      assurance: assurance,
      validators: [_, v | _]
    } do
      a1 = %{assurance | validator_index: 2}
      a2 = %{assurance | validator_index: 1}
      a3 = %{assurance | validator_index: 3}
      # use signer as validator in all indexes
      state = %{state | curr_validators: List.duplicate(v, 6)}

      assert [a2, a1, a3] == Assurance.assurances_for_new_block([a1, a2, a3], state)
    end

    test "filter out assurances with invalid signatures", %{
      state: state,
      assurance: assurance,
      validators: validators
    } do
      state = %{state | curr_validators: validators}
      invalid_assurance = build(:assurance, validator_index: 0)

      assert [assurance] ==
               Assurance.assurances_for_new_block([assurance, invalid_assurance], state)
    end
  end
end
