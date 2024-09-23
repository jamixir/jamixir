defmodule UtilsTest do
  use ExUnit.Case

  describe "invert bits" do
    test "inverts bits correctly" do
      binary_value = <<0b10101010, 0b11001100>>
      assert Utils.invert_bits(binary_value) == <<0b01010101, 0b00110011>>
    end
  end
end
