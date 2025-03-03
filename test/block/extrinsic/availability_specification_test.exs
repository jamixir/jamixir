defmodule Block.Extrinsic.AvailabilitySpecificationTest do
  alias Util.MerkleTree
  alias Block.Extrinsic.AvailabilitySpecification, as: AS
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
      {decoded, _} = AS.decode(encoded)
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

  describe "from_execution/3" do
    use Sizes

    test "calculates erasure root" do
      segments = [<<0::@export_segment_size*8>>, <<1::@export_segment_size*8>>]

      bundle_binary = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      exp_erasure_root = AS.calculate_erasure_root(bundle_binary, segments)

      spec = AS.from_execution(Hash.one(), bundle_binary, segments)

      assert spec.work_package_hash == Hash.one()
      assert spec.erasure_root == exp_erasure_root
      assert spec.exports_root == MerkleTree.merkle_root(segments)
      assert spec.segment_count == 2
      assert spec.length == 10
    end
  end
end
