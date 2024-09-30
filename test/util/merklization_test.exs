defmodule Util.MerklizationTest do
  use ExUnit.Case
  alias Util.Hash
  alias Util.Merklization

  describe "encode_branch/2" do
    test "encoding branch returns correct length for 512 bits" do
      data_left = "test data left"
      hash_left = Hash.blake2b_n(data_left, 32)

      data_right = "test data right"
      hash_right = Hash.blake2b_n(data_right, 32)

      merk = Merklization.encode_branch(hash_left, hash_right)

      assert bit_size(merk) == 512
    end

    test "encoding branch returns correct a bitstring that starts with a 0 as first bit" do
      data_left = "test data left"
      hash_left = Hash.blake2b_n(data_left, 32)

      data_right = "test data right"
      hash_right = Hash.blake2b_n(data_right, 32)

      merk = Merklization.encode_branch(hash_left, hash_right)

      <<merk_first_bit::1, _rest_bits::bitstring-size(511)>> = merk
      assert merk_first_bit == 0
    end

    test "encoding branch returns correct a bitstring that starts with a 1 as separator between hashes" do
      data_left = "test data left"
      hash_left = Hash.blake2b_n(data_left, 32)

      data_right = "test data right"
      hash_right = Hash.blake2b_n(data_right, 32)

      merk = Merklization.encode_branch(hash_left, hash_right)

      <<_first_bits::bitstring-size(256), merk_separator_bit::1, _rest_bits::bitstring-size(255)>> =
        merk

      assert merk_separator_bit == 1
    end
  end

  describe "encode_leaf/2" do
    test "encodes an embedded value leaf correctly" do
      key =
        <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
          25, 26, 27, 28, 29, 30, 31>>

      value =
        <<100, 200, 50, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
          21, 22, 23, 24, 25, 26, 27, 28>>

      encode_Test = Merklization.encode_leaf(key, value)

      <<1::1, leaf_type::1, _byte_size::6, _key::binary-size(31), _value::binary-size(32)>> =
        encode_Test

      assert leaf_type == 1
    end

    test "encodes a regular leaf correctly" do
      key =
        <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
          25, 26, 27, 28, 29, 30, 31>>

      value =
        <<100, 200, 50, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
          21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40>>

      encode_Test = Merklization.encode_leaf(key, value)

      <<1::1, leaf_type::1, _byte_size::6, _key::binary-size(31), _value::binary-size(32)>> =
        encode_Test

      assert leaf_type == 0
    end

#  Test examples by Daniel
#     byte_size(value) < 32
# byte_size(value) == 32
# byte_size(value) > 32

  end

  # describe "merklization/1" do
  #   test "testing merkelization total size of 64 bytes" do
  #     value_test = "Hello Jamixir"
  #     hash_value = Hash.blake2b_n(value_test, 64)
  #     leaf = Merklization.merklize(hash_value)
  #     assert bit_size(leaf) == 512
  #   end

  #   test "testing merkelization call branch" do
  #     value_test = "Hello Jamixir"
  #     hash_value = Hash.blake2b_n(value_test, 64)

  #     branch = Merklization.merklize(hash_value)

  #     << branch_bit::1, _rest_bits::bitstring-size(511)>> = branch
  #     assert branch_bit == 1
  #   end

  #   test "testing merkelization call leaf" do
  #     value_test = "Hello Jamixir"
  #     hash_value = Hash.blake2b_n(value_test, 64)

  #     leaf = Merklization.merklize(hash_value)

  #     <<_::1, rest_bits::bitstring-size(511)>> = hash_value

  #     <<leaf_first_bit::1, _rest_bits::bitstring-size(511)>> = leaf
  #     assert leaf_first_bit == 0
  #   end

  # end

  describe "bits" do
    test "bits for multiple octets" do
      octets = <<5, 0, 5>>
      expected_bits = [1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0]
      assert Merklization.bits(octets) == expected_bits
    end
  end
end
