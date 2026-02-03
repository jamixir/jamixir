defmodule Jamixir.SqlStorageTest do
  alias Block.Extrinsic.Preimage
  alias Block.Extrinsic.Disputes.Judgement
  alias Storage.AvailabilityRecord
  alias Util.Hash
  alias Jamixir.SqlStorage
  alias Block.Extrinsic.Assurance
  alias Storage.PreimageMetadataRecord
  use ExUnit.Case, async: true
  use Jamixir.DBCase
  import Jamixir.Factory

  describe "assurance operations" do
    test "save and retrieve assurance" do
      assurance1 = build(:assurance, validator_index: 0)
      assurance2 = build(:assurance, validator_index: 1)
      assert {:ok, _record} = SqlStorage.save(assurance1)
      assert {:ok, _record} = SqlStorage.save(assurance2)
      [record1, record2] = SqlStorage.get_all(Assurance)
      assert record1 == assurance1
      assert record2 == assurance2
    end

    test "save updates existing assurance" do
      assurance = build(:assurance, validator_index: 0)
      assert {:ok, _record} = SqlStorage.save(assurance)
      updated_assurance = %Assurance{assurance | bitfield: <<1::344>>}
      assert {:ok, _record} = SqlStorage.save(updated_assurance)
      [record] = SqlStorage.get_all(Assurance)
      assert record == updated_assurance
    end

    test "get assurance for specific hash and validator" do
      assurance = build(:assurance, validator_index: 2)
      assert {:ok, _record} = SqlStorage.save(assurance)
      record = SqlStorage.get(Assurance, [assurance.hash, 2])
      assert record == assurance
    end

    test "get all assurance for specific hash" do
      SqlStorage.save(build(:assurance, validator_index: 2, hash: <<1::256>>))
      SqlStorage.save(build(:assurance, validator_index: 3, hash: <<1::256>>))
      SqlStorage.save(build(:assurance, validator_index: 4, hash: <<1::256>>))

      records = SqlStorage.get_all(Assurance, <<1::256>>)
      assert length(records) == 3

      SqlStorage.clean(Assurance)
      records = SqlStorage.get_all(Assurance, <<1::256>>)
      assert Enum.empty?(records)
    end

    test "get assurance returns nil when not found" do
      record = SqlStorage.get(Assurance, [Hash.random(), 99])
      assert record == nil
    end
  end

  describe "judgement operations" do
    test "save and retrieve judgements by epoch" do
      judgement1 = build(:judgement, validator_index: 0)
      judgement2 = build(:judgement, validator_index: 1)
      epoch = 42
      hash = Hash.random()
      assert {:ok, _record} = SqlStorage.save(judgement1, hash, epoch)
      assert {:ok, _record} = SqlStorage.save(judgement2, hash, epoch)
      [record1, record2] = SqlStorage.get_all(Judgement, epoch)
      assert record1 == judgement1
      assert record2 == judgement2
    end
  end

  describe "preimage metadata operations" do
    test "save and retrieve preimage metadata" do
      pm1 = %PreimageMetadataRecord{hash: <<1::256>>, service_id: 7, length: 32}
      pm2 = %PreimageMetadataRecord{hash: <<2::256>>, service_id: 8, length: 32}

      assert {:ok, _hash} = SqlStorage.save(pm1)
      assert {:ok, _hash} = SqlStorage.save(pm2)
      [saved_pm1, saved_pm2] = SqlStorage.get_all(Preimage, :pending)
      assert saved_pm1.hash == pm1.hash
      assert saved_pm1.service_id == pm1.service_id
      assert saved_pm1.length == pm1.length
      assert saved_pm2.hash == pm2.hash
      assert saved_pm2.service_id == pm2.service_id
      assert saved_pm2.length == pm2.length
      assert saved_pm1.status == :pending
      assert saved_pm2.status == :pending
    end

    test "mark preimage as included in service" do
      hash = Hash.random()
      preimage_metadata = %PreimageMetadataRecord{hash: hash, service_id: 7, length: 32}

      assert {:ok, _hash} = SqlStorage.save(preimage_metadata)
      SqlStorage.mark_preimage_included(hash, 7)
      [pm] = SqlStorage.get_all(Preimage, :included)
      assert pm.service_id == 7
      [] = SqlStorage.get_all(Preimage, :pending)
    end

    test "same preimage can be in multiple services" do
      hash = Hash.random()
      preimage_metadata1 = %PreimageMetadataRecord{hash: hash, service_id: 10, length: 32}
      preimage_metadata2 = %PreimageMetadataRecord{hash: hash, service_id: 11, length: 32}

      assert {:ok, _hash} = SqlStorage.save(preimage_metadata1)
      assert {:ok, _hash} = SqlStorage.save(preimage_metadata2)
      assert {:error, _hash} = SqlStorage.save(preimage_metadata2)

      included = SqlStorage.get_all(Preimage)
      assert length(included) == 2
    end
  end

  describe "availability record operations" do
    test "save and retrieve availability record" do
      ar = %AvailabilityRecord{
        work_package_hash: <<1::256>>,
        bundle_length: 100,
        erasure_root: <<2::256>>,
        exports_root: <<3::256>>,
        segment_count: 5,
        shard_index: 3
      }

      SqlStorage.save(ar)

      # Verify the record was actually inserted
      [saved] = Jamixir.Repo.all(AvailabilityRecord)
      assert saved.work_package_hash == <<1::256>>
      assert saved.bundle_length == 100
      assert saved.erasure_root == <<2::256>>
      assert saved.exports_root == <<3::256>>
      assert saved.segment_count == 5
      assert saved.shard_index == 3
    end

    test "save fails when shard_index is missing" do
      ar = %AvailabilityRecord{
        work_package_hash: <<1::256>>,
        bundle_length: 100,
        erasure_root: <<2::256>>,
        exports_root: <<3::256>>,
        segment_count: 5
      }

      assert {:error, _} = SqlStorage.save(ar)

      # Verify nothing was inserted
      assert Jamixir.Repo.all(AvailabilityRecord) == []
    end

    test "save updates existing availability record on conflict" do
      work_package_hash = Hash.random()

      ar1 = %AvailabilityRecord{
        work_package_hash: work_package_hash,
        bundle_length: 100,
        erasure_root: <<2::256>>,
        exports_root: <<3::256>>,
        segment_count: 5,
        shard_index: 3
      }

      ar2 = %AvailabilityRecord{
        work_package_hash: work_package_hash,
        bundle_length: 200,
        erasure_root: <<4::256>>,
        exports_root: <<5::256>>,
        segment_count: 10,
        shard_index: 7
      }

      assert {:ok, _record} = SqlStorage.save(ar1)
      assert {:ok, _record} = SqlStorage.save(ar2)

      # Should have updated the existing record, not created a new one
      records = Jamixir.Repo.all(AvailabilityRecord)
      assert length(records) == 1

      [saved] = records
      assert saved.work_package_hash == work_package_hash
      assert saved.bundle_length == 200
      assert saved.erasure_root == <<4::256>>
      assert saved.exports_root == <<5::256>>
      assert saved.segment_count == 10
      assert saved.shard_index == 7
    end
  end
end
