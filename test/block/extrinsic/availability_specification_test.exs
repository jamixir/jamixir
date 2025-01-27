defmodule Block.Extrinsic.AvailabilitySpecificationTest do
  alias Block.Extrinsic.AvailabilitySpecification
  alias Util.{Hash, Hex}
  use ExUnit.Case
  import Jamixir.Factory

  setup do
    {:ok, availability: build(:availability_specification, work_package_hash: Hash.one())}
  end

  describe "encode / decode" do
    test "encode/1", %{availability: availability} do
      assert Codec.Encoder.encode(availability) ==
               "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04\x02\0"
    end

    test "decode/1", %{availability: availability} do
      encoded = Encodable.encode(availability)
      {decoded, _} = AvailabilitySpecification.decode(encoded)
      assert decoded == availability
    end
  end

  describe "to_json/1" do
    test "encodes availability specification to json", %{availability: availability} do
      assert Codec.JsonEncoder.encode(availability) == %{
               hash: Hex.encode16(availability.work_package_hash, prefix: true),
               exports_count: availability.segment_count,
               length: availability.length,
               erasure_root: Hex.encode16(availability.erasure_root, prefix: true),
               exports_root: Hex.encode16(availability.exports_root, prefix: true)
             }
    end
  end
end
