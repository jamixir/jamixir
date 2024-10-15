defmodule Util.HashTest do
  use ExUnit.Case

  alias Util.Hash

  describe "blake2b_n/2" do
    test "returns correct length for n=32" do
      data = "test data"
      hash = Hash.blake2b_n(data, Sizes.hash())
      assert byte_size(hash) == Sizes.hash()
    end

    test "returns correct length for n=16" do
      data = "test data"
      hash = Hash.blake2b_n(data, 16)
      assert byte_size(hash) == 16
    end

    test "returns correct length for n=8" do
      data = "test data"
      hash = Hash.blake2b_n(data, 8)
      assert byte_size(hash) == 8
    end

    test "returns correct length for n=4" do
      data = "test data"
      hash = Hash.blake2b_n(data, 4)
      assert byte_size(hash) == 4
    end

    test "returns correct length for n=1" do
      data = "test data"
      hash = Hash.blake2b_n(data, 1)
      assert byte_size(hash) == 1
    end
  end

  describe "blake2b_256/1" do
    test "returns correct length for 256-bit hash" do
      data = "test data"
      hash = Hash.default(data)
      assert byte_size(hash) == Sizes.hash()
    end

    test "returns correct hash for known input" do
      data = "test data"
      expected_hash = <<0xEAB94977A17791D0C089FE9E393261B3AB667CF0E8456632A842D905C468CF65::256>>
      assert Hash.default(data) == expected_hash
    end
  end

  describe "default/1" do
    assert Hash.default("test data") == Hash.default("test data")
  end
end
