defmodule RefinementContextTest do
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, rc: build(:refinement_context)}
  end

  test "encode/1 smoke test", %{rc: rc} do
    assert Encodable.encode(rc) ==
             "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\0\0\0"
  end

  test "encode/1 with nil prerequisite", %{rc: rc} do
    no_pre = Map.put(rc, :prerequisite, nil)

    assert Encodable.encode(no_pre) ==
             "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x05\0\0\0\0"
  end

  test "decode/1 smoke test", %{rc: rc} do
    encoded = Encodable.encode(rc)
    {decoded, _} = RefinementContext.decode(encoded)
    assert rc == decoded
  end

  test "decode/1 with prerequisite not nil", %{rc: rc} do
    rc = put_in(rc.prerequisite, Hash.random())
    encoded = Encodable.encode(rc)
    {decoded, _} = RefinementContext.decode(encoded)
    assert rc == decoded
  end
end
