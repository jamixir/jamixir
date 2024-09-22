defmodule Block.Extrinsic.AssuranceTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Assurance
  alias Codec.Encoder
  alias System.State.Validator
  alias Util.{Crypto, Hash}

  setup_all do
    hp = :crypto.strong_rand_bytes(32)
    keys = 1..3 |> Enum.map(fn _ -> :crypto.generate_key(:eddsa, :ed25519) end)

    validators =
      build_list(3, :validator)
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        %Validator{v | ed25519: elem(Enum.at(keys, i), 0)}
      end)

    [_, {_, s2}, _] = keys
    payload = SigningContexts.jam_available() <> Hash.default(hp <> "av")
    signature = Crypto.sign(payload, s2)

    assurance =
      build(:assurance,
        hash: hp,
        validator_index: 1,
        assurance_values: "av",
        signature: signature
      )

    %{hp: hp, assurance: assurance, validators: validators}
  end

  setup_all do
    parent_hash = :crypto.strong_rand_bytes(32)
    keys = 1..3 |> Enum.map(fn _ -> :crypto.generate_key(:eddsa, :ed25519) end)

    validators =
      build_list(3, :validator)
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        %Validator{v | ed25519: elem(Enum.at(keys, i), 0)}
      end)

    [_, {_, s2}, _] = keys
    payload = SigningContexts.jam_available() <> Hash.default(parent_hash <> "av")
    signature = Crypto.sign(payload, s2)

    valid_assurance =
      build(:assurance,
        hash: parent_hash,
        validator_index: 1,
        assurance_values: "av",
        signature: signature
      )

    %{
      parent_hash: parent_hash,
      valid_assurance: valid_assurance,
      validators: validators
      # v1: v1,
      # v2: v2,
      # key1: key1
    }
  end

  describe "Assurance encoding" do
    test "encodes an Assurance struct correctly" do
      assurance = build(:assurance)

      encoded = Encoder.encode(assurance)

      expected = <<
        # hash (32 bytes)
        assurance.hash::binary,
        # assurance_values (43 bytes, 344 bits)
        assurance.assurance_values::bitstring,
        # validator_index (2 bytes)
        assurance.validator_index::little-16,
        # signature (64 bytes)
        assurance.signature::binary
      >>

      assert encoded == expected
    end
  end

  describe "validate_assurances/2" do
    test "returns :ok for valid assurances", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      assurances = [assurance]
      assert :ok == Assurance.validate_assurances(assurances, hp, validators)
    end

    test "returns error when assurance hash doesn't match parent hash", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      d_assurance = %{assurance | hash: :crypto.strong_rand_bytes(32)}
      assurances = [assurance, d_assurance]

      assert {:error, "Invalid assurance"} ==
               Assurance.validate_assurances(assurances, hp, validators)
    end

    test "returns error when validator index is out of bounds", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      d_assurance = %{assurance | validator_index: 5_000}
      assurances = [d_assurance]

      assert {:error, :invalid_signature} ==
               Assurance.validate_assurances(assurances, hp, validators)
    end

    test "returns :ok for empty list of assurances", %{hp: hp, validators: validators} do
      assert :ok == Assurance.validate_assurances([], hp, validators)
    end

    test "returns :ok for single valid assurance", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      assert :ok == Assurance.validate_assurances([assurance], hp, validators)
    end

    # Uncomment this test if you implement the validator_index uniqueness check
    test "returns error for duplicate validator indices", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      duplicate_assurance = %{assurance | validator_index: assurance.validator_index}
      assurances = [assurance, duplicate_assurance]

      assert {:error, :duplicates} =
               Assurance.validate_assurances(assurances, hp, validators)
    end

    test "error when validator_index is not ordered", %{
      assurance: assurance,
      hp: hp,
      validators: validators
    } do
      higher_index = %{assurance | validator_index: assurance.validator_index + 1}

      assert {:error, :not_in_order} ==
               Assurance.validate_assurances([higher_index, assurance], hp, validators)
    end

    test "returns :error for invalid signature assurances", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      invalid_assurance = %{assurance | signature: :crypto.strong_rand_bytes(64)}

      Assurance.validate_assurances([invalid_assurance], hp, validators)
    end

    test "returns :error for invalid validator index", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      invalid_assurance = %{assurance | validator_index: 2}

      assert {:error, :invalid_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators)
    end

    test "returns :error for invalid assurance_values", %{
      hp: hp,
      assurance: assurance,
      validators: validators
    } do
      invalid_assurance = %{assurance | assurance_values: "other"}

      assert {:error, :invalid_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators)
    end
  end
end
