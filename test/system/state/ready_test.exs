defmodule System.State.ReadyTest do
  use ExUnit.Case, async: true
  use Codec.Encoder
  import Jamixir.Factory
  alias System.State.Ready

  describe "encode/1" do
    test "encodes a Ready struct correctly" do
      ready = build(:ready)
      assert is_binary(e(ready))
    end
  end

  describe "decode/1" do
    test "decodes a binary back into a Ready struct" do
      ready = build(:ready)
      {decoded, _} = Ready.decode(e(ready))

      assert decoded == ready
    end
  end
end
