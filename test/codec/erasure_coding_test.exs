defmodule ErasureCodingTest do
  use ExUnit.Case
  alias ErasureCoding
  import Util.Hex, only: [b16: 1]

  describe "encode/1" do
    core_count = %{"tiny" => 2, "full" => 342}

    for type <- ["tiny", "full"] do
      for size <- ["3", "32", "100", "4096", "4104", "10000"] do
        file_name = "#{type}/ec-#{size}"

        test_case =
          File.read!("../jam-test-vectors/erasure/#{file_name}.json")
          |> Jason.decode!()
          |> JsonDecoder.from_json()

        @tag test_case: test_case
        @tag cores: core_count[type]
        test "test encode decode #{file_name}", %{test_case: test_case, cores: cores} do
          bin = test_case["data"]
          encoded = ErasureCoding.encode(bin, cores)
          assert encoded == test_case["shards"]
        end

        @tag test_case: test_case
        @tag cores: core_count[type]
        test "test decode #{file_name}", %{test_case: test_case, cores: cores} do
          bin = test_case["data"]
          shards = test_case["shards"]

          # take random C indices from the V available shards
          indices = Enum.take_random(0..(length(shards) - 1), cores)
          selected_shards = Enum.map(indices, &Enum.at(shards, &1))

          decoded = ErasureCoding.decode(selected_shards, indices, byte_size(bin), cores)
          assert decoded == bin
        end
      end
    end

    # https://github.com/jam-duna/jamtestnet/issues/139
    @tag :skip
    test "encode wp bundle" do
      result = ErasureCoding.encode(<<0x1421199ADDAC7C87873A0000::96>>, 2)

      b16result = for b <- result, do: b16(b)

      assert b16result == [
               "0x1421ddac873a",
               "0x199a7c870000",
               "0xc75ae79a6a22",
               "0xcae146b1ed18",
               "0xedadf41bf3c3",
               "0xe016553074f9"
             ]
    end

    test "segment vector" do
      test_case =
        Jason.decode!("""
        {
        "data" : "20ffffffff511611dddbb4dc1fdf564814f71094fb22248cce581f0811e0c1c72839300000cea6d514511611dddbb4dc1fdf564814f71094fb22248cce581f0811e0c1c728000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001393000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "shards" : [ "20ffffffff511611dddbb4dc1fdf564814f71094fb22248cce581f0811e0c1c72839300000cea6d514511611dddbb4dc1fdf564814f71094fb22248cce581f0811e0c1c728000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001393000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "12bab1ba7ccc003f6caceca1c6a34bf546bc1754d018be6eebc94906d88de599a9202500c39c60a4f5cc003f6caceca1c6a34bf546bc1754d018be6eebc94906d88de5991f00cf021e1500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "32454e45839d162eb177587dd97c1dbd524b07c02b3a9ae22591560ec96d245e81191500c352c671e19d162eb177587dd97c1dbd524b07c02b3a9ae22591560ec96d245e3700cf03272500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "6913e513e275425fa28eef80d28c4625711cb2a5999612f0567f840f3c483cd923cfc5009ad3c88aa975425fa28eef80d28c4625711cb2a5999612f0567f840f3c483cd99000ab0431f500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "49ec1aec1d24544e7f555b5ccd53106d65eba23162b4367c98279b072da8fd1e0bf6f5009a1d6e5fbd24544e7f555b5ccd53106d65eba23162b4367c98279b072da8fd1eb800ab0508c500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ]
        }
        """)

      bin = test_case["data"] |> Base.decode16!(case: :lower)
      expected_shards = test_case["shards"] |> Enum.map(&Base.decode16!(&1, case: :lower))

      assert ErasureCoding.encode(bin, 2) == expected_shards
    end
  end

  describe "decode/2" do
    test "smoke decode" do
      string = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      [s0, s1, s2, s3, s4, s5] = ErasureCoding.encode(string, 2)

      assert ErasureCoding.decode([s0, s3], [0, 3], 10, 2) == string
      assert ErasureCoding.decode([s1, s2], [1, 2], 10, 2) == string
      assert ErasureCoding.decode([s4, s5], [4, 5], 10, 2) == string
      # wrong indices should not match
      assert ErasureCoding.decode([s4, s5], [1, 2], 10, 2) != string
      # not enough shards
      assert ErasureCoding.decode([s1], [1], 10, 2) == :error
    end
  end
end
