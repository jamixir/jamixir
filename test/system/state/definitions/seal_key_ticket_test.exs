defmodule System.State.SealKeyTicketTest do
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      assert Codec.Encoder.encode(build(:single_seal_key_ticket)) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0"
    end
  end
end
