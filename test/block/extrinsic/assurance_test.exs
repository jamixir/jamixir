defmodule Block.Extrinsic.AssuranceTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Assurance
  alias Codec.Encoder

  setup_all do
    parent_hash = :crypto.strong_rand_bytes(32)
    valid_assurance = build(:assurance, hash: parent_hash, validator_index: 1)
    %{parent_hash: parent_hash, valid_assurance: valid_assurance}
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
      parent_hash: parent_hash,
      valid_assurance: valid_assurance
    } do
      assurances = [valid_assurance, build(:assurance, hash: parent_hash, validator_index: 2)]
      assert :ok == Assurance.validate_assurances(assurances, parent_hash)
    end

    test "returns error when assurance hash doesn't match parent_hash", %{
      parent_hash: parent_hash,
      valid_assurance: valid_assurance
    } do
      invalid_assurance = %{valid_assurance | hash: :crypto.strong_rand_bytes(32)}
      assurances = [valid_assurance, invalid_assurance]

      assert {:error, "Invalid assurance"} ==
               Assurance.validate_assurances(assurances, parent_hash)
    end

    test "returns :ok for empty list of assurances", %{parent_hash: parent_hash} do
      assert :ok == Assurance.validate_assurances([], parent_hash)
    end

    test "returns :ok for single valid assurance", %{
      parent_hash: parent_hash,
      valid_assurance: valid_assurance
    } do
      assert :ok == Assurance.validate_assurances([valid_assurance], parent_hash)
    end

    # Uncomment this test if you implement the validator_index uniqueness check
    test "returns error for duplicate validator indices", %{
      parent_hash: parent_hash,
      valid_assurance: valid_assurance
    } do
      duplicate_assurance = %{valid_assurance | validator_index: valid_assurance.validator_index}
      assurances = [valid_assurance, duplicate_assurance]
      assert {:error, :duplicates} = Assurance.validate_assurances(assurances, parent_hash)
    end

    test "error when validator_index is not ordered", %{
      valid_assurance: valid_assurance,
      parent_hash: parent_hash
    } do
      higher_index = %{valid_assurance | validator_index: valid_assurance.validator_index + 1}

      assert {:error, :not_in_order} ==
               Assurance.validate_assurances([higher_index, valid_assurance], parent_hash)
    end
  end
end
