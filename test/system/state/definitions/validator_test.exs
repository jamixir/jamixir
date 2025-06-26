defmodule System.State.ValidatorTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias System.State.Validator
  alias TestHelper, as: TH
  alias Util.Hash
  import Util.Hex

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
      offenders = MapSet.new([Hash.four()])

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

  describe "IP and port from metadata" do
    test "extracts IPv6 and port from metadata" do
      # IPv6: 2001:0db8:85a3:0000:0000:8a2e:0370:7334 (16 bytes)
      # Port: 8080 (2 bytes, little endian = <<0x90, 0x1F>>)
      metadata = decode16!("20010db885a3000000008a2e03707334901f")

      v = build(:validator, metadata: metadata)

      assert Validator.ip_address(v) == {8193, 3512, 34_211, 0, 0, 35_374, 880, 29_492}
      assert Validator.port(v) == 8080
    end

    test "handles empty metadata" do
      v = build(:validator, metadata: <<>>)

      assert Validator.ip_address(v) == nil
      assert Validator.port(v) == nil
    end

    test "handles metadata bigger than 18" do
      v =
        build(:validator,
          metadata: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19>>
        )

      assert Validator.ip_address(v) != nil
      assert Validator.port(v) != nil
    end

    test "handles invalid metadata length" do
      v = build(:validator, metadata: <<1, 2, 3>>)
      assert Validator.ip_address(v) == nil
    end
  end

  describe "neighbours/4" do
    setup do
      prev_validators = for v <- 1..9, do: TH.create_validator(v)
      curr_validators = for v <- 10..18, do: TH.create_validator(v)
      next_validators = for v <- 19..27, do: TH.create_validator(v)

      {:ok,
       prev_validators: prev_validators,
       curr_validators: curr_validators,
       next_validators: next_validators}
    end

    # GRID
    # 1 2 3     10 11 12     19 20 21
    # 4 5 6     13 14 15     22 23 24
    # 7 8 9     16 17 18     25 26 27

    test "returns the correct neighbours", c do
      [p01, _, _, _, p05 | _] = c.prev_validators
      [c10, c11, c12, c13, c14, c15, c16, c17, _] = c.curr_validators
      [n19, _, _, _, n23 | _] = c.next_validators

      assert Validator.neighbours(c10, c.prev_validators, c.curr_validators, c.next_validators) ==
               MapSet.new([c11, c12, c13, c16, p01, n19])

      assert Validator.neighbours(c14, c.prev_validators, c.curr_validators, c.next_validators) ==
               MapSet.new([c11, c13, c15, c17, p05, n23])
    end

    test "return empty set when validator is not in grid", c do
      assert Validator.neighbours(
               TH.create_validator(100),
               c.prev_validators,
               c.curr_validators,
               c.next_validators
             ) == MapSet.new()
    end

    test "return empty set when list sizes are different", c do
      [p01 | _] = c.prev_validators

      assert Validator.neighbours(
               p01,
               c.prev_validators ++ [TH.create_validator(100)],
               c.curr_validators,
               c.next_validators
             ) == MapSet.new()

      assert Validator.neighbours(
               p01,
               c.prev_validators,
               c.curr_validators,
               c.next_validators ++ [TH.create_validator(100)]
             ) == MapSet.new()
    end
  end
end
