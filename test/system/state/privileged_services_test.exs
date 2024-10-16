defmodule System.State.PrivilegedServicesTest do
  use ExUnit.Case
  import Jamixir.Factory

  describe "encode/1" do
    test "encode smoke test" do
      assert Codec.Encoder.encode(build(:privileged_services)) == "\0\0\0\0\0\0\0\0\0\0\0\0\0"
    end
  end
end
