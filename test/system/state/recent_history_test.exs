defmodule RecentHistoryTest do
  use ExUnit.Case

  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee
  alias Block.Header
  alias System.State.RecentHistory.RecentBlock
  alias System.State.{BeefyCommitmentMap, RecentHistory}
  alias Util.{Hash, MerkleTree, MMR}
  import Jamixir.Factory
  use Codec.Encoder

  describe "update_latest_state_root_/2" do
    test "returns empty list when given nil" do
      header = %Header{prior_state_root: "s"}
      assert RecentHistory.update_latest_state_root_(nil, header).blocks === []
    end

    test "returns empty list when given empty list" do
      header = %Header{prior_state_root: "s"}

      assert RecentHistory.update_latest_state_root_(%RecentHistory{}, header).blocks ===
               []
    end

    test "returns list with modified first block when given non-empty list" do
      header = %Header{prior_state_root: "s"}
      most_recent_block1 = %RecentBlock{state_root: nil}
      most_recent_block2 = %RecentBlock{state_root: "s2"}

      block_history =
        %RecentHistory{}
        |> RecentHistory.add(most_recent_block1)
        |> RecentHistory.add(most_recent_block2)

      expected = [most_recent_block1, %RecentBlock{state_root: "s"}]

      assert RecentHistory.update_latest_state_root_(block_history, header).blocks ===
               expected
    end
  end

  describe "calculate_recent_history_" do
    test "handles empty guarantees list" do
      recent_history = %RecentHistory{}
      beefy_commitment_map = BeefyCommitmentMap.new([{1, Hash.one()}])

      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == %{}
    end

    test "handles nil beefy_commitment_map" do
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{work_package_hash: Hash.one()}
        }
      }

      recent_history = %RecentHistory{}
      beefy_commitment_map = nil

      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).accumulated_result_mmr == [Hash.zero()]
    end

    test "handles empty recent_history.blocks" do
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{work_package_hash: Hash.one()}
        }
      }

      recent_history = %RecentHistory{}
      beefy_commitment_map = BeefyCommitmentMap.new([{1, Hash.one()}])

      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == %{ Hash.one => Hash.zero}
    end

    test "handles non-empty recent_history.blocks" do
      previous_block = %RecentHistory.RecentBlock{
        header_hash: Hash.one(),
        accumulated_result_mmr: [Hash.two()],
        state_root: Hash.one(),
        work_report_hashes: %{Hash.three() => Hash.zero()}
      }

      recent_history = %RecentHistory{blocks: [previous_block]}

      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.four,
            exports_root: Hash.five
          }
        }
      }

      beefy_commitment_map = BeefyCommitmentMap.new([{2, Hash.five}])

      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 2
      assert Enum.at(result.blocks, -1).work_report_hashes == %{Hash.four => Hash.five}
    end

    test "verifies work_package_hashes are extracted correctly" do
      guarantee1 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.one,
            exports_root: Hash.two
          }
        }
      }

      guarantee2 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.two,
            exports_root: Hash.three
          }
        }
      }

      recent_history = %RecentHistory{}
      beefy_commitment_map = BeefyCommitmentMap.new([{3, Hash.three()}])

      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee1, guarantee2],
          recent_history,
          beefy_commitment_map
        )

      assert Enum.at(result.blocks, -1).work_report_hashes == %{
        Hash.one => Hash.two,
        Hash.two => Hash.three
      }
    end

    test "correctly updates RecentHistory when list is full" do
      # Create distinct recent blocks with unique work_reports_hashes for identification
      blocks =
        for i <- 1..8 do
          %RecentHistory.RecentBlock{
            header_hash: <<i::256>>,
            accumulated_result_mmr: [<<i::256>>],
            state_root: <<i::256>>,
            work_report_hashes: %{<<i::256>> => Hash.zero()}
          }
        end

      # Ensure RecentHistory is full
      recent_history = %RecentHistory{blocks: blocks}

      # Create a new guarantee with a unique work_package_hash
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: <<9::256>>,
            exports_root: Hash.five
          }
        }
      }

      beefy_commitment_map = BeefyCommitmentMap.new([{1, Hash.one()}])

      # Call the function to add a new block
      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      # Check that the length remains 8
      assert length(result.blocks) == 8

      # Verify that the oldest block was removed (i.e., the block with work_report_hashes == [Hash.one()])
      assert Enum.at(result.blocks, 0).work_report_hashes == %{Hash.two => Hash.zero}

      # Verify that the newest block was added (i.e., the block with work_report_hashes == [<<9::256>>])
      assert Enum.at(result.blocks, -1).work_report_hashes == %{<<9::256>> => Hash.five}
    end

    test "correctly links inputs to MMR and work_package_hashes" do
      # Create a beefy commitment map
      beefy_commitment_map =
        BeefyCommitmentMap.new([{1, <<11::256>>}, {2, <<22::256>>}])

      # Create guarantees with specific work_package_hashes
      guarantee1 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.one,
            exports_root: Hash.two
          }
        }
      }

      guarantee2 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.two,
            exports_root: Hash.three
          }
        }
      }

      # Call the function to update recent history
      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee1, guarantee2],
          %RecentHistory{},
          beefy_commitment_map
        )

      # Verify that the MMR and work_package_hashes are correctly linked
      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == %{
        Hash.one => Hash.two,
        Hash.two => Hash.three
      }

      # Construct the expected Merkle tree root from the beefy_commitment_map
      expected_merkle_root =
        MapSet.to_list(beefy_commitment_map)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {service, hash} ->
          encoded_index = Codec.Encoder.encode_little_endian(service, 4)
          <<encoded_index::binary, hash::binary>>
        end)
        |> MerkleTree.well_balanced_merkle_root(&Hash.keccak_256/1)

      # Verify that the accumulated_result_mmr is based on the well-balanced Merkle root
      expected_mmr_roots = MMR.append(MMR.new(), expected_merkle_root).roots

      assert Enum.at(result.blocks, -1).accumulated_result_mmr == expected_mmr_roots
    end

    test "verifies state root is all zeros" do
      # Create a guarantee with specific work_package_hashes
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.one,
            exports_root: Hash.two
          }
        }
      }

      # Call the function to update recent history
      result =
        RecentHistory.calculate_recent_history_(
          %Header{},
          [guarantee],
          %RecentHistory{},
          BeefyCommitmentMap.new([{2, <<5::256>>}])
        )

      # Verify that the state root in the newly added block is all zeros
      assert Enum.at(result.blocks, -1).state_root == Hash.zero()
    end

    test "verifies header hash" do
      header = %Header{block_seal: Hash.one()}

      # Call the function to update recent history
      result =
        RecentHistory.calculate_recent_history_(header, [], %RecentHistory{}, nil)

      # Verify that the state root in the newly added block is all zeros
      assert Enum.at(result.blocks, -1).header_hash == h(e(header))
    end
  end

  describe "encode/1" do
    test "encode recent history smoke test" do
      e(build(:recent_history))
    end
  end

  describe "get_well_balanced_merkle_root/1" do
    test "returns Hash.zero() for nil input" do
      assert RecentHistory.get_well_balanced_merkle_root(nil) == Hash.zero()
    end

    test "returns Hash.zero() for empty MapSet" do
      assert RecentHistory.get_well_balanced_merkle_root(MapSet.new()) == Hash.zero()
    end

    test "calculates merkle root for non-empty MapSet" do
      map = BeefyCommitmentMap.new([{1, Hash.one()}, {2, Hash.two()}])
      result = RecentHistory.get_well_balanced_merkle_root(map)
      refute result == Hash.zero()
    end
  end
end
