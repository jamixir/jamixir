defmodule ErasureCodingTest do
  use ExUnit.Case
  alias ErasureCoding
  import Util.Hex
  import TestVectorUtil
  use Codec.Encoder

  describe "encode/1" do
    for type <- ["tiny", "full"] do
      for size <- ["bundle_10", "bundle_272", "segment_4104"] do
        file_name = "test_#{size}_#{type}"
        @tag file_name: file_name
        @tag cores: if(type == "tiny", do: 2, else: 342)

        test "smoke test #{file_name}", %{file_name: file_name, cores: cores} do
          json =
            File.read("./test/codec/#{file_name}.json")
            |> elem(1)
            |> Jason.decode!()
            |> JsonDecoder.from_json()

          bin = json["segment"]
          encoded = ErasureCoding.encode(bin, cores)
          assert encoded == json["shards"]
        end
      end
    end
  end
end
