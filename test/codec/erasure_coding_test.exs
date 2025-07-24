defmodule ErasureCodingTest do
  use ExUnit.Case
  alias ErasureCoding

  describe "encode/1" do
    core_count = %{"tiny" => 2, "full" => 342}

    for type <- ["tiny", "full"] do
      for size <- ["bundle_10", "bundle_272", "segment_4104"] do
        file_name = "test_#{size}_#{type}"

        test_case =
          File.read!("./test/codec/#{file_name}.json")
          |> Jason.decode!()
          |> JsonDecoder.from_json()

        @tag test_case: test_case
        @tag cores: core_count[type]
        test "test encode decode #{file_name}", %{test_case: test_case, cores: cores} do
          bin = test_case["segment"]
          encoded = ErasureCoding.encode(bin, cores)
          assert encoded == test_case["shards"]
        end

        @tag test_case: test_case
        @tag cores: core_count[type]
        test "test decode #{file_name}", %{test_case: test_case, cores: cores} do
          bin = test_case["segment"]
          shards = test_case["shards"]

          # take random indices from shards
          indices = Enum.take_random(0..(length(shards) - 1), cores)
          shards = Enum.map(indices, &Enum.at(shards, &1))

          decoded = ErasureCoding.decode(shards, indices, byte_size(bin), cores)
          assert decoded == bin
        end
      end
    end
  end

  describe "decode/2" do
    test "smoke decode" do
      string = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      [s0, s1, s2, s3, s4, s5] = ErasureCoding.encode(string, 2)

      assert ErasureCoding.decode([s0, s3], [0, 3], 10, 2) == string
      assert ErasureCoding.decode([s1, s2], [1, 2], 10, 2) == string
      assert ErasureCoding.decode([s4, s5], [4, 5], 10, 2) == string
      assert ErasureCoding.decode([s4, s5], [1, 2], 10, 2) != string
      # not enough shards
      assert ErasureCoding.decode([s1], [1], 10, 2) == :error
    end
  end
end
