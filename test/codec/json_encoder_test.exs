defmodule Codec.JsonEncoderTest do
  use ExUnit.Case
  alias Codec.JsonEncoder
  alias Util.Hash
  import Jamixir.Factory
  import Util.Hex, only: [b16: 1]

  describe "encode/1" do
    test "encodes list of list of hashes" do
      # Create some test binary data representing hashes
      hash1 = <<1, 2, 3>>
      hash2 = <<4, 5, 6>>
      hash3 = <<7, 8, 9>>

      input = [
        [hash1, hash2],
        [hash3]
      ]

      expected = [
        ["0x010203", "0x040506"],
        ["0x070809"]
      ]

      assert JsonEncoder.encode(input) == expected
    end

    test "encodes empty lists" do
      input = [[], []]
      expected = [[], []]

      assert JsonEncoder.encode(input) == expected
    end

    test "encodes single hash" do
      hash = <<1, 2, 3>>
      assert JsonEncoder.encode(hash) == "0x010203"
    end

    test "encodes RecentBlock" do
      block =
        build(:recent_block,
          work_package_hashes: %{Hash.random() => Hash.random(), Hash.random() => Hash.random()},
          beefy_root: Hash.random()
        )

      json = JsonEncoder.encode(block)

      assert json == %{
               header_hash: b16(block.header_hash),
               state_root: b16(block.state_root),
               beefy_root: b16(block.beefy_root),
               reported:
                 block.work_package_hashes
                 |> Enum.map(fn {hash, exports_root} ->
                   %{hash: b16(hash), exports_root: b16(exports_root)}
                 end)
             }
    end

    test "encodes RecentHistory" do
      history = build(:recent_history)
      json = JsonEncoder.encode(history)
      assert json == Enum.map(history.blocks, &JsonEncoder.encode/1)
    end

    test "encodes Safrole" do
      safrole = build(:safrole)
      json = JsonEncoder.encode(safrole)

      assert json == %{
               gamma_k: Enum.map(safrole.pending, &JsonEncoder.encode/1),
               gamma_s: %{tickets: Enum.map(safrole.slot_sealers, &JsonEncoder.encode/1)},
               gamma_a: Enum.map(safrole.ticket_accumulator, &JsonEncoder.encode/1),
               gamma_z: b16(safrole.epoch_root)
             }
    end
  end
end
