defmodule System.PVMTest do
  use ExUnit.Case
  alias System.PVM

  describe "skip/2" do
    test "finds next opcode under normal operation" do
      # Example: 1010_0000 represents two instructions,
      # first opcode at bit 0, second at bit 2
      k = <<0b10100000::8>>
      # From bit 0, skips 1 bit to reach bit 1
      assert PVM.skip(0, k) == 1
      assert PVM.skip(2, k) == 5
    end

    test "handles position one before end of bitstring" do
      # Last bit is 0, followed by appended 1
      k = <<0b11111110::8>>
      # Should find the appended 1
      assert PVM.skip(6, k) == 1
    end

    test "handles position at end of bitstring" do
      k = <<0b11111111::8>>
      # Should find the appended 1 immediately
      assert PVM.skip(7, k) == 0
    end

    test "caps at 24 when encountering long sequence of zeros" do
      # Create a bitstring with a single 1 followed by many zeros
      # 1 followed by 31 zeros
      k = <<0b10000000::8, 0::24>>
      # Should cap at 24 even though more zeros follow
      assert PVM.skip(0, k) == 24
    end

    test "handles position beyond end of bitstring" do
      k = <<0b0000::4>>
      assert PVM.skip(8, k) == 0
    end
  end
end
