defmodule Util.MerklizationTest do
  use ExUnit.Case
  alias Util.Hash
  alias Util.Merklization

  # Formula (293) v0.3.4: TESTS

  describe "encode_branch/2 (l,r)" do
    test "encode_branch with simple values" do
      # 256-bit value with only the first bit set
      l = <<1::256>>
      # 256-bit value with only the second bit set
      r = <<2::256>>

      result = Merklization.encode_branch(l, r)

      assert is_list(result)
      assert length(result) == 512
      assert Enum.at(result, 0) == 0
    end

    test "encode_branch with random inputs" do
      for _ <- 1..100 do
        l = :crypto.strong_rand_bytes(32)
        r = :crypto.strong_rand_bytes(32)

        result = Merklization.encode_branch(l, r)

        assert is_list(result)
        assert length(result) == 512
        assert Enum.at(result, 0) == 0
      end
    end
  end

  # Formula (294) v0.3.4: TESTS

  describe "encode_leaf/2" do
    test "encode_leaf when byte_size(value) < 32 (Embebed)" do

      key = :crypto.strong_rand_bytes(31)

      value = :crypto.strong_rand_bytes(16)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == 512

      assert Enum.slice(result, 0, 2) == [1, 0]

      assert Enum.slice(result, 2, 6) == [0, 0, 0, 0, 1, 0]

    end

    test "encode_leaf when byte_size(value) == 32" do

      key = :crypto.strong_rand_bytes(31)

      value = :crypto.strong_rand_bytes(32)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == 512

      assert Enum.slice(result, 0, 2) == [1, 0]

    end

    test "encode_leaf when byte_size(value) > 32" do
      key = :crypto.strong_rand_bytes(31)
      value = :crypto.strong_rand_bytes(33)

      result = Merklization.encode_leaf(key, value)

      assert length(result) == 512

      assert Enum.slice(result, 0, 8) == [1, 1, 0, 0, 0, 0, 0, 0]

    end
  end

  # Formula (295) v0.3.4: TESTS

  # Formula (296) v0.3.4: TESTS

  ### 3.7.3

  describe "bits" do
    test "bits function with single byte" do
      # Binary representation: 00101010
      input = <<42>>
      expected = [0, 1, 0, 1, 0, 1, 0, 0]
      assert Merklization.bits(input) == expected
    end

    test "bits for multiple octets(bytes)" do
      octets = <<5, 0, 5>>
      # 5 in binary
      expected_bits = [
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        # 0 in binary
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        # 5 in binary
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0
      ]

      assert Merklization.bits(octets) == expected_bits
    end

    test "bits function with empty binary" do
      input = <<>>
      expected = []
      assert Merklization.bits(input) == expected
    end

    test "bits function with all bits set" do
      # Binary: 11111111 11111111
      input = <<255, 255>>
      expected_bits = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
      assert Merklization.bits(input) == expected_bits
    end
  end
end
