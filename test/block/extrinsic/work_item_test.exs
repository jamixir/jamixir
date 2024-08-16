defmodule WorkItemTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.WorkItem

  setup do
    {:ok, wi: build(:work_item)}
  end

  describe "encode/1" do
    test "encodes a work result", %{wi: wi} do
      assert Codec.Encoder.encode(wi) ==
               "\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x01\x02\x03\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x06\a\0\0\0\b\0"
    end
  end
end
