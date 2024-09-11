defmodule System.State.ValidatorTest do
  alias System.State.Validator
  use ExUnit.Case
  import Jamixir.Factory

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
      assert Validator.from_json(Codec.JsonEncoder.to_json(v)) == v
    end
  end
end
