defmodule Util.MMRTest do
  use ExUnit.Case
  alias Util.MMR
  alias Util.Hash

  defp hash(data), do: Hash.blake2b_256(data)

  test "create new MMR" do
    mmr = MMR.new()
    assert %MMR{roots: []} = mmr
  end

  test "create MMR from list of hashes" do
    list_of_hashes = [<<1::256>>, <<2::256>>, <<3::256>>]
    mmr = MMR.from(list_of_hashes)
    assert MMR.roots(mmr) == list_of_hashes

    mmr = MMR.from([])
    assert MMR.roots(mmr) == []
  end

  test "convert MMR to list of hashes" do
    list_of_hashes = [<<1::256>>, <<2::256>>, <<3::256>>]
    mmr = MMR.from(list_of_hashes)
    assert MMR.to_list(mmr) == list_of_hashes
  end

  test "append elements to MMR and verify roots" do
    mmr = MMR.new()

    # Append the first element
    data1_hash = hash("data1")
    mmr = MMR.append(mmr, data1_hash)
    assert MMR.roots(mmr) == [data1_hash]

    # Append the second element
    data2_hash = hash("data2")
    hash1_2 = hash(data1_hash <> data2_hash)
    mmr = MMR.append(mmr, data2_hash)
    assert MMR.roots(mmr) == [nil, hash1_2]

    # Append the third element
    data3_hash = hash("data3")
    mmr = MMR.append(mmr, data3_hash)
    assert MMR.roots(mmr) == [data3_hash, hash1_2]

    # Append the fourth element
    data4_hash = hash("data4")
    hash3_4 = hash(data3_hash <> data4_hash)
    hash1_2_3_4 = hash(hash1_2 <> hash3_4)
    mmr = MMR.append(mmr, data4_hash)
    assert MMR.roots(mmr) == [nil, nil, hash1_2_3_4]

    # Append the fifth element
    data5_hash = hash("data5")
    mmr = MMR.append(mmr, data5_hash)
    assert MMR.roots(mmr) == [data5_hash, nil, hash1_2_3_4]
  end

  test "append more elements and verify roots" do
    hashes = [
      hash("data1"),
      hash("data2"),
      hash("data3"),
      hash("data4"),
      hash("data5")
    ]

    mmr =
      MMR.new()
      |> MMR.append(Enum.at(hashes, 0))
      |> MMR.append(Enum.at(hashes, 1))
      |> MMR.append(Enum.at(hashes, 2))
      |> MMR.append(Enum.at(hashes, 3))
      |> MMR.append(Enum.at(hashes, 4))

    hash1_2 = hash(Enum.at(hashes, 0) <> Enum.at(hashes, 1))
    hash3_4 = hash(Enum.at(hashes, 2) <> Enum.at(hashes, 3))
    hash1_2_3_4 = hash(hash1_2 <> hash3_4)
    assert MMR.roots(mmr) == [Enum.at(hashes, 4), nil, hash1_2_3_4]
  end

  test "append elements and verify intermediate roots" do
    mmr = MMR.new()

    # Append the first element
    data1_hash = hash("data1")
    mmr = MMR.append(mmr, data1_hash)
    assert MMR.roots(mmr) == [data1_hash]

    # Append the second element
    data2_hash = hash("data2")
    hash1_2 = hash(data1_hash <> data2_hash)
    mmr = MMR.append(mmr, data2_hash)
    assert MMR.roots(mmr) == [nil, hash1_2]

    # Append the third element
    data3_hash = hash("data3")
    mmr = MMR.append(mmr, data3_hash)
    assert MMR.roots(mmr) == [data3_hash, hash1_2]

    # Append the fourth element
    data4_hash = hash("data4")
    hash3_4 = hash(data3_hash <> data4_hash)
    hash1_2_3_4 = hash(hash1_2 <> hash3_4)
    mmr = MMR.append(mmr, data4_hash)
    assert MMR.roots(mmr) == [nil, nil, hash1_2_3_4]

    # Append the fifth element
    data5_hash = hash("data5")
    mmr = MMR.append(mmr, data5_hash)
    assert MMR.roots(mmr) == [data5_hash, nil, hash1_2_3_4]
  end
end
