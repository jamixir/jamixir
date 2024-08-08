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
    mmr = MMR.append(mmr, "data1")
    assert MMR.roots(mmr) == [hash("data1")]

    mmr = MMR.append(mmr, "data2")
    data1_hash = hash("data1")
    data2_hash = hash("data2")
    hash1_2 = hash(data1_hash <> data2_hash)
    assert MMR.roots(mmr) == [nil, hash1_2]

    mmr = MMR.append(mmr, "data3")
    data3_hash = hash("data3")
    assert MMR.roots(mmr) == [data3_hash, hash1_2]

    mmr = MMR.append(mmr, "data4")
    data4_hash = hash("data4")
    hash3_4 = hash(data3_hash <> data4_hash)
    hash1_2_3_4 = hash(hash1_2 <> hash3_4)
    assert MMR.roots(mmr) == [nil, nil, hash1_2_3_4]

    mmr = MMR.append(mmr, "data5")
    data5_hash = hash("data5")
    assert MMR.roots(mmr) == [data5_hash, nil, hash1_2_3_4]
  end

  test "append more elements and verify roots" do
    mmr = MMR.new()
    mmr = MMR.append(mmr, "data1")
    mmr = MMR.append(mmr, "data2")
    mmr = MMR.append(mmr, "data3")
    mmr = MMR.append(mmr, "data4")
    mmr = MMR.append(mmr, "data5")

    data1_hash = hash("data1")
    data2_hash = hash("data2")
    data3_hash = hash("data3")
    data4_hash = hash("data4")
    data5_hash = hash("data5")

    hash1_2 = hash(data1_hash <> data2_hash)
    hash3_4 = hash(data3_hash <> data4_hash)
    hash1_2_3_4 = hash(hash1_2 <> hash3_4)

    assert MMR.roots(mmr) == [data5_hash, nil, hash1_2_3_4]
  end

  test "append elements and verify intermediate roots" do
    mmr = MMR.new()
    mmr = MMR.append(mmr, "data1")
    assert MMR.roots(mmr) == [hash("data1")]

    mmr = MMR.append(mmr, "data2")
    data1_hash = hash("data1")
    data2_hash = hash("data2")
    hash1_2 = hash(data1_hash <> data2_hash)
    assert MMR.roots(mmr) == [nil, hash1_2]

    mmr = MMR.append(mmr, "data3")
    data3_hash = hash("data3")
    assert MMR.roots(mmr) == [data3_hash, hash1_2]

    mmr = MMR.append(mmr, "data4")
    data4_hash = hash("data4")
    hash3_4 = hash(data3_hash <> data4_hash)
    hash1_2_3_4 = hash(hash1_2 <> hash3_4)
    assert MMR.roots(mmr) == [nil, nil, hash1_2_3_4]

    mmr = MMR.append(mmr, "data5")
    data5_hash = hash("data5")
    assert MMR.roots(mmr) == [data5_hash, nil, hash1_2_3_4]
  end
end
