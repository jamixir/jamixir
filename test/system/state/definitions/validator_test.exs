defmodule System.State.ValidatorTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.Validator
  alias TestHelper, as: TH
  alias Util.Hash

  setup_all do
    next_validators = for v <- 1..3, do: TH.create_validator(v)
    RingVrf.init_ring_context(length(next_validators))
    offenders = MapSet.new([Hash.one(), Hash.three()])
    {:ok, next_validators: next_validators, offenders: offenders}
  end

  describe "key/1" do
    test "validator key is the concatenation of all keys" do
      v = build(:validator)
      assert Validator.key(v) == v.bandersnatch <> v.ed25519 <> v.bls <> v.metadata
    end
  end

  describe "encode/1" do
    test "encode smoke test" do
      v = build(:validator)
      assert Codec.Encoder.encode(v) == Validator.key(v)
    end
  end

  describe "from_json/1" do
    test "from_json smoke test" do
      v = build(:validator)
      json = Codec.JsonEncoder.encode(v)
      assert Validator.from_json(json) == v
    end
  end

  describe "nullify_offenders/2" do
    test "nullifies validators that are in the offenders set", %{
      next_validators: next_validators,
      offenders: offenders
    } do
      result = Validator.nullify_offenders(next_validators, offenders)

      # Validator 1 and 3 are nullified, 2 is not

      assert TH.nullified?(Enum.at(result, 0))
      assert Enum.at(result, 1) == Enum.at(next_validators, 1)
      assert TH.nullified?(Enum.at(result, 2))
    end

    test "returns the same validators if none are in the offenders set", %{
      next_validators: next_validators
    } do
      # No matching offenders
      offenders = MapSet.new([<<4::256>>])

      result = Validator.nullify_offenders(next_validators, offenders)

      assert result == next_validators
    end

    test "handles an empty offenders set", %{
      next_validators: next_validators
    } do
      # No matching offenders
      offenders = MapSet.new()

      result = Validator.nullify_offenders(next_validators, offenders)

      assert result == next_validators
    end

    test "return empty when next_validators is empty", %{} do
      assert Validator.nullify_offenders([], MapSet.new()) == []
    end
  end
end
