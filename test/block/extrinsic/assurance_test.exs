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

    [_, {_, s2}, _] = keys
    payload = SigningContexts.jam_available() <> Hash.default(hp <> <<0::344>>)
    signature = Crypto.sign(payload, s2)

    Application.put_env(:jamixir, Constants, AssuranceConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)

    assurance =
      build(:assurance,
        hash: hp,
        validator_index: 1,
        bitfield: <<0::344>>,
        signature: signature
      )

    %{hp: hp, assurance: assurance, validators: validators, core_reports: [], s2: s2}
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

      assert {:error, "Invalid assurance"} ==
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

      assert {:error, :invalid_signature} ==
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

      assert {:error, :invalid_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end

    test "returns :error for invalid validator index", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      invalid_assurance = %{assurance | validator_index: 2}

      assert {:error, :invalid_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end

    test "returns :error for invalid bitfield", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      core_reports: cr
    } do
      invalid_assurance = %{assurance | bitfield: "other"}

      assert {:error, :invalid_signature} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, cr)
    end

    # Formula (129) v0.4.5
    test "returns :error when assurance bit is set but core report is null", %{
      hp: hp,
      assurance: assurance,
      validators: validators,
      s2: s2
    } do
      payload = SigningContexts.jam_available() <> Hash.default(hp <> <<1::1, 0::7>>)
      signature = Crypto.sign(payload, s2)
      invalid_assurance = %{assurance | signature: signature, bitfield: <<1::1, 0::7>>}

      assert {:error, "Invalid core reports bits"} ==
               Assurance.validate_assurances([invalid_assurance], hp, validators, [nil])
    end
  end
end
