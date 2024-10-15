defmodule Block.Extrinsic.AvailabilitySpecificationTest do
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, availability: build(:availability_specification, work_package_hash: Hash.one())}
  end

  test "encode/1", %{availability: availability} do
    assert Codec.Encoder.encode(availability) ==
             "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04"
  end
end
