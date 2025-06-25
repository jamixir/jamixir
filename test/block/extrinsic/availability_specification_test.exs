defmodule Block.Extrinsic.AvailabilitySpecificationTest do
  alias Block.Extrinsic.AvailabilitySpecification, as: AS
  alias Util.{MerkleTree, Hash}
  use ExUnit.Case
  import Jamixir.Factory
  import Util.Hex, only: [b16: 1]
  import Mox

  setup do
    Application.put_env(:jamixir, :erasure_coding, ErasureCodingMock)
    stub(ErasureCodingMock, :do_erasure_code, fn _ -> [<<>>] end)

    on_exit(fn ->
      Application.delete_env(:jamixir, :erasure_coding)
    end)

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
               hash: b16(availability.work_package_hash),
               exports_count: availability.segment_count,
               length: availability.length,
               erasure_root: b16(availability.erasure_root),
               exports_root: b16(availability.exports_root)
             }
    end
  end

  describe "from_execution/3" do
    import Codec.Encoder

    test "calculates erasure root" do
      erasure_coded_piece = 1
      segments = [t(erasure_coded_piece), t(erasure_coded_piece)]

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
