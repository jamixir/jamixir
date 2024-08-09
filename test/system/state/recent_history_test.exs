defmodule System.State.RecentHistoryTest do
  use ExUnit.Case

  alias System.State.{RecentHistory, BeefyCommitmentMap}
  alias System.State.RecentHistory.RecentBlock
  alias Block.Header
  alias Block.Extrinsic.Guarantee
  alias Util.{Hash, MMR, MerkleTree}

  describe "update_latest_posterior_state_root/2" do
    test "returns empty list when given nil" do
      header = %Header{prior_state_root: "s"}
      assert RecentHistory.update_latest_posterior_state_root(nil, header).blocks === []
    end

    test "returns empty list when given empty list" do
      header = %Header{prior_state_root: "s"}

      assert RecentHistory.update_latest_posterior_state_root(RecentHistory.new(), header).blocks ===
               []
    end

    test "returns list with modified first block when given non-empty list" do
      header = %Header{prior_state_root: "s"}
      most_recent_block1 = %RecentBlock{state_root: nil}
      most_recent_block2 = %RecentBlock{state_root: "s2"}

      block_history =
        RecentHistory.new()
        |> RecentHistory.add(most_recent_block1)
        |> RecentHistory.add(most_recent_block2)

      expected = [most_recent_block1, %RecentBlock{state_root: "s"}]

      assert RecentHistory.update_latest_posterior_state_root(block_history, header).blocks ===
               expected
    end
  end

  describe "posterior_recent_history" do
    test "handles empty guarantees list" do
      recent_history = %RecentHistory{}
      beefy_commitment_map = %BeefyCommitmentMap{commitments: [{1, <<1::256>>}]}

      result =
        System.State.RecentHistory.posterior_recent_history(
          %Header{},
          [],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == []
    end

    test "handles nil beefy_commitment_map" do
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<1::256>>}
        }
      }

      recent_history = %RecentHistory{}
      beefy_commitment_map = nil

      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).accumulated_result_mmr == [<<0::256>>]
    end

    test "handles empty recent_history.blocks" do
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<1::256>>}
        }
      }

      recent_history = %RecentHistory{}
      beefy_commitment_map = %BeefyCommitmentMap{commitments: [{1, <<1::256>>}]}

      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == [<<1::256>>]
    end

    test "handles non-empty recent_history.blocks" do
      previous_block = %RecentHistory.RecentBlock{
        header_hash: <<1::256>>,
        accumulated_result_mmr: [<<2::256>>],
        state_root: <<1::256>>,
        work_report_hashes: [<<3::256>>]
      }

      recent_history = %RecentHistory{blocks: [previous_block]}

      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<4::256>>}
        }
      }

      beefy_commitment_map = %BeefyCommitmentMap{commitments: [{2, <<5::256>>}]}

      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      assert length(result.blocks) == 2
      assert Enum.at(result.blocks, -1).work_report_hashes == [<<4::256>>]
    end

    test "verifies work_package_hashes are extracted correctly" do
      guarantee1 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<1::256>>}
        }
      }

      guarantee2 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<2::256>>}
        }
      }

      recent_history = %RecentHistory{}
      beefy_commitment_map = %BeefyCommitmentMap{commitments: [{3, <<3::256>>}]}

      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee1, guarantee2],
          recent_history,
          beefy_commitment_map
        )

      assert Enum.at(result.blocks, -1).work_report_hashes == [<<1::256>>, <<2::256>>]
    end

    test "correctly updates RecentHistory when list is full" do
      # Create distinct recent blocks with unique work_reports_hashes for identification
      blocks =
        for i <- 1..8 do
          %RecentHistory.RecentBlock{
            header_hash: <<i::256>>,
            accumulated_result_mmr: [<<i::256>>],
            state_root: <<i::256>>,
            work_report_hashes: [<<i::256>>]
          }
        end

      # Ensure RecentHistory is full
      recent_history = %RecentHistory{blocks: blocks}

      # Create a new guarantee with a unique work_package_hash
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<9::256>>}
        }
      }

      beefy_commitment_map = %BeefyCommitmentMap{commitments: [{1, <<1::256>>}]}

      # Call the function to add a new block
      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee],
          recent_history,
          beefy_commitment_map
        )

      # Check that the length remains 8
      assert length(result.blocks) == 8

      # Verify that the oldest block was removed (i.e., the block with work_report_hashes == [<<1::256>>])
      assert Enum.at(result.blocks, 0).work_report_hashes == [<<2::256>>]

      # Verify that the newest block was added (i.e., the block with work_report_hashes == [<<9::256>>])
      assert Enum.at(result.blocks, -1).work_report_hashes == [<<9::256>>]
    end

    test "correctly links inputs to MMR and work_package_hashes" do
      # Create a beefy commitment map
      beefy_commitment_map = %BeefyCommitmentMap{
        commitments: [
          {1, <<11::256>>},
          {2, <<22::256>>}
        ]
      }

      # Create guarantees with specific work_package_hashes
      guarantee1 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<1::256>>}
        }
      }

      guarantee2 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<2::256>>}
        }
      }

      # Initialize recent history with one block
      recent_history = RecentHistory.new()

      # Call the function to update recent history
      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee1, guarantee2],
          recent_history,
          beefy_commitment_map
        )

      # Verify that the MMR and work_package_hashes are correctly linked
      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == [<<1::256>>, <<2::256>>]

      # Construct the expected Merkle tree root from the beefy_commitment_map
      expected_merkle_root =
        beefy_commitment_map.commitments
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {service_index, hash} ->
          encoded_index = ScaleEncoding.encode_integer(service_index)
          <<encoded_index::binary, hash::binary>>
        end)
        |> MerkleTree.well_balanced_merkle_root(&Hash.keccak_256/1)

      # Verify that the accumulated_result_mmr is based on the well-balanced Merkle root
      expected_mmr_roots =
        MMR.new()
        |> MMR.append(expected_merkle_root)
        |> MMR.roots()

      assert Enum.at(result.blocks, -1).accumulated_result_mmr == expected_mmr_roots
    end

    test "verifies state root is all zeros" do
      # Create a guarantee with specific work_package_hashes
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specfication: %Guarantee.AvailabilitySpecification{work_package_hash: <<1::256>>}
        }
      }

      # Initialize recent history
      recent_history = RecentHistory.new()

      # Call the function to update recent history
      result =
        System.State.RecentHistory.posterior_recent_history(
          %{},
          [guarantee],
          recent_history,
          %BeefyCommitmentMap{commitments: [{2, <<5::256>>}]}
        )

      # Verify that the state root in the newly added block is all zeros
      assert Enum.at(result.blocks, -1).state_root == <<0::256>>
    end
  end
end
