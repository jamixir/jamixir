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

  describe "from_package_execution/3" do
    use Sizes

    test "calculates erasure root", %{availability: availability} do
      segments = [<<0::@export_segment_size*8>>, <<1::@export_segment_size*8>>]

      bundle_binary = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

      spec =
        AvailabilitySpecification.from_package_execution(
          Hash.one(),
          bundle_binary,
          segments
        )

      assert spec.work_package_hash == Hash.one()
    end
  end
end
