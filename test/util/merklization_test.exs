defmodule Util.MerklizationTest do
  use ExUnit.Case
  alias Util.Hash
  alias Util.Merklization

  describe "encode_branch" do
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
  end

  describe "encode_leaf" do
    test "testing encode_leaf function, first bit must be 1" do
      key_test = "12334kknknknkn32233"
      hash_key = Hash.blake2b_n(key_test, 64)
      data_test = "Hello Jamixir"
      hash_data = Hash.blake2b_n(data_test, 32)

      leaf = Merklization.encode_leaf(hash_key, hash_data)

      <<node_type::1, _rest_bits::bitstring-size(511)>> = leaf

      assert node_type == 1
    end

    test "testing encode_leaf function" do
      key_test = "12334kknknknkn32233"
      hash_key = Hash.blake2b_n(key_test, 64)
      data_test = "Hello Jamixir"
      hash_data = Hash.blake2b_n(data_test, 32)
      leaf = Merklization.encode_leaf(hash_key, hash_data)
      assert bit_size(leaf) == 512
    end
  end

  describe "merklization" do
    test "testing merkelization total size of 64 bytes" do
      value_test = "Hello Jamixir"
      hash_value = Hash.blake2b_n(value_test, 64)
      leaf = Merklization.merklize(hash_value)
      assert bit_size(leaf) == 512
    end

    test "testing merkelization call branch" do
      value_test = "Hello Jamixir"
      hash_value = Hash.blake2b_n(value_test, 64)
      leaf = Merklization.merklize(hash_value)
      assert bit_size(leaf) == 512
    end

    # test "testing merkelization call leaf" do
    #   value_test = "Hello Jamixir"
    #   hash_value = Hash.blake2b_n(value_test,64)

    #   hash_value = <<1::1, _rest_bits::bitstring-size(511)>>
    #   leaf = Merklization.merklize(hash_value)

    #   <<leaf_first_bit::1, _rest_bits::bitstring-size(511)>> = leaf

    #   assert leaf_first_bit == 1
    # end

    test "testing merkelization call leaf" do
      value_test = "Hello Jamixir"
      hash_value = Hash.blake2b_n(value_test, 64)

      <<_::1, rest_bits::bitstring-size(511)>> = hash_value

      hash_value = <<1::1, rest_bits::bitstring-size(511)>>

      leaf = Merklization.merklize(hash_value)

      <<leaf_first_bit::1, _rest_bits::bitstring-size(511)>> = leaf

      assert leaf_first_bit == 1
    end
  end
end
