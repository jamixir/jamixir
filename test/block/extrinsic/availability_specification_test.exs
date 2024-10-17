defmodule Block.Extrinsic.AvailabilitySpecificationTest do
  alias Block.Extrinsic.AvailabilitySpecification
  alias Util.Hash
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, availability: build(:availability_specification, work_package_hash: Hash.one())}
  end

  describe "encode / decode" do
    test "encode/1", %{availability: availability} do
      assert Codec.Encoder.encode(availability) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04"
    end

    test "decode/1", %{availability: availability} do
      encoded = Encodable.encode(availability)
      {decoded, _} = AvailabilitySpecification.decode(encoded)
      assert decoded == availability
    end
  end
end
