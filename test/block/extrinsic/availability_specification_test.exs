defmodule Block.Extrinsic.AvailabilitySpecificationTest do
  alias Block.Extrinsic.AvailabilitySpecification, as: AS
  use ExUnit.Case
  import Jamixir.Factory
  import Codec.Encoder
  alias Util.{Hash, MerkleTree}
  import Util.Hex, only: [b16: 1]

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

  describe "b_clubs/1" do
    test "calculates b_clubs correctly for small bundle size" do
      bundle_binary = <<0x1421199ADDAC7C87873A::80>>
      result = AS.b_clubs(bundle_binary)
      assert length(result) == Constants.validator_count()
      assert Enum.all?(result, fn h -> byte_size(h) == 32 end)
    end

    test "calculates b_clubs correctly for large bundle size" do
      bundle_binary = <<1::size(64 * Constants.erasure_coded_piece_size() + 8)>>
      result = AS.b_clubs(bundle_binary)
      assert length(result) == Constants.validator_count()
      assert Enum.all?(result, fn h -> byte_size(h) == 32 end)
    end
  end

  describe "s_clubs/1" do
    test "calculates s_clubs correctly for small number of segments" do
      segments = generate_hash_chain_segments(3)

      result = AS.s_clubs(segments)
      assert length(result) == Constants.validator_count()
      assert Enum.all?(result, fn h -> byte_size(h) == 32 end)
    end

    test "calculates s_clubs correctly for large number of segments" do
      segments = generate_hash_chain_segments(100)
      result = AS.s_clubs(segments)
      assert length(result) == Constants.validator_count()
      assert Enum.all?(result, fn h -> byte_size(h) == 32 end)
    end
  end

  def generate_hash_chain_segments(n) do
    Stream.iterate(Hash.blake2b_256(""), &Hash.blake2b_256/1)
    |> Stream.flat_map(&:binary.bin_to_list/1)
    |> Stream.chunk_every(Constants.segment_size())
    |> Stream.map(&IO.iodata_to_binary/1)
    |> Stream.take(n)
    |> Enum.to_list()
  end
end
