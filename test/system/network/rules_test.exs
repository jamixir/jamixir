defmodule System.Network.RulesTest do
  use ExUnit.Case

  alias System.Network.Rules

  describe "preferred_initiator/2" do
    test "prefers a when a31 > 127, b31 <= 127, and a > b" do
      # 31st byte > 127
      a = <<0::248, 128::8, 0::8>>
      # 31st byte <= 127
      b = <<0::248, 0::8, 0::8>>
      assert Rules.preferred_initiator(a, b) == a
    end

    test "prefers b when a31 <= 127, b31 <= 127, and a > b" do
      # 31st byte <= 127
      a = <<0::248, 0::8, 1::8>>
      # 31st byte <= 127
      b = <<0::248, 0::8, 0::8>>
      assert Rules.preferred_initiator(a, b) == b
    end

    test "prefers a when a31 > 127, b31 > 127, and a < b" do
      # 31st byte > 127
      a = <<0::248, 128::8, 0::8>>
      # 31st byte > 127
      b = <<0::248, 255::8, 0::8>>
      assert Rules.preferred_initiator(a, b) == a
    end

    test "prefers b when a31 <= 127, b31 > 127, and a < b" do
      # 31st byte <= 127
      a = <<0::248, 0::8, 0::8>>
      # 31st byte > 127
      b = <<0::248, 128::8, 0::8>>
      assert Rules.preferred_initiator(b, a) == b
    end

    test "handles equal keys" do
      key = <<0::248, 128::8, 0::8>>
      assert Rules.preferred_initiator(key, key) == key
    end

    test "handles keys with different lengths" do
      a = <<0::248, 128::8, 0::8>>
      b = <<0::248, 0::8, 0::8, 0::8>>
      assert Rules.preferred_initiator(a, b) in [a, b]
    end
  end
end
