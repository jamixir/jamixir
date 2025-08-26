defmodule RecentHistoryTest do
  use ExUnit.Case

  alias System.State.RecentHistory.AccumulationOutput
  alias Block.Extrinsic.AvailabilitySpecification
  alias Block.Extrinsic.Guarantee
  alias Block.Header
  alias System.State.RecentHistory.RecentBlock
  alias System.State.{RecentHistory}
  alias Util.{Hash, MerkleTree, MMR}
  import Jamixir.Factory
  import Codec.Encoder

  describe "update_latest_state_root/2" do
    test "returns empty list when given nil" do
      header = %Header{prior_state_root: "s"}
      assert RecentHistory.update_latest_state_root(nil, header).blocks === []
    end

    test "returns empty list when given empty list" do
      header = %Header{prior_state_root: "s"}

      assert RecentHistory.update_latest_state_root(%RecentHistory{}, header).blocks ===
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

      assert RecentHistory.update_latest_state_root(block_history, header.prior_state_root).blocks ===
               expected
    end
  end

  describe "transition" do
    test "handles empty guarantees list" do
      recent_history = %RecentHistory{}
      accumulation_outputs = [%AccumulationOutput{service: 1, accumulated_output: Hash.one()}]

      result =
        RecentHistory.transition(
          %Header{},
          recent_history,
          [],
          accumulation_outputs
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == %{}
      assert result.beefy_belt == [Hash.keccak_256(<<1::service(), Hash.one()::binary>>)]
    end

    test "handles nil accumulation_outputs" do
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{work_package_hash: Hash.one()}
        }
      }

      recent_history = %RecentHistory{}
      accumulation_outputs = nil

      result =
        RecentHistory.transition(
          %Header{},
          recent_history,
          [guarantee],
          accumulation_outputs
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).beefy_root == Hash.zero()
      assert result.beefy_belt == [Hash.zero()]
    end

    test "handles empty recent_history.blocks" do
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{work_package_hash: Hash.one()}
        }
      }

      recent_history = %RecentHistory{}
      accumulation_outputs = [%AccumulationOutput{service: 1, accumulated_output: Hash.one()}]

      result =
        RecentHistory.transition(
          %Header{},
          recent_history,
          [guarantee],
          accumulation_outputs
        )

      assert length(result.blocks) == 1
      assert Enum.at(result.blocks, -1).work_report_hashes == %{Hash.one() => Hash.zero()}

      assert Enum.at(result.blocks, -1).beefy_root ==
               Hash.keccak_256(<<1::service(), Hash.one()::binary>>)
    end

    test "handles non-empty recent_history.blocks" do
      previous_block = %RecentBlock{
        header_hash: Hash.one(),
        beefy_root: [Hash.two()],
        state_root: Hash.one(),
        work_report_hashes: %{Hash.three() => Hash.zero()}
      }

      recent_history = %RecentHistory{blocks: [previous_block]}

      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.four(),
            exports_root: Hash.five()
          }
        }
      }

      accumulation_outputs = [%AccumulationOutput{service: 2, accumulated_output: Hash.five()}]

      result =
        RecentHistory.transition(
          %Header{},
          recent_history,
          [guarantee],
          accumulation_outputs
        )

      assert length(result.blocks) == 2
      assert Enum.at(result.blocks, -1).work_report_hashes == %{Hash.four() => Hash.five()}
    end

    test "verifies work_package_hashes are extracted correctly" do
      guarantee1 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.one(),
            exports_root: Hash.two()
          }
        }
      }

      guarantee2 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.two(),
            exports_root: Hash.three()
          }
        }
      }

      recent_history = %RecentHistory{}
      accumulation_outputs = [%AccumulationOutput{service: 3, accumulated_output: Hash.three()}]

      result =
        RecentHistory.transition(
          %Header{},
          recent_history,
          [guarantee1, guarantee2],
          accumulation_outputs
        )

      assert Enum.at(result.blocks, -1).work_report_hashes == %{
               Hash.one() => Hash.two(),
               Hash.two() => Hash.three()
             }
    end

    test "correctly updates RecentHistory when list is full" do
      # Create distinct recent blocks with unique work_reports_hashes for identification
      blocks =
        for hash <- 1..8 do
          %RecentHistory.RecentBlock{
            header_hash: t(hash),
            beefy_root: [t(hash)],
            state_root: t(hash),
            work_report_hashes: %{t(hash) => Hash.zero()}
          }
        end

      # Ensure RecentHistory is full
      recent_history = %RecentHistory{blocks: blocks}

      # Create a new guarantee with a unique work_package_hash
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: <<9::hash()>>,
            exports_root: Hash.five()
          }
        }
      }

      accumulation_outputs = [%AccumulationOutput{service: 1, accumulated_output: Hash.one()}]

      # Call the function to add a new block
      result =
        RecentHistory.transition(
          %Header{},
          recent_history,
          [guarantee],
          accumulation_outputs
        )

      # Check that the length remains 8
      assert length(result.blocks) == 8

      # Verify that the oldest block was removed (i.e., the block with work_report_hashes == [Hash.one()])
      assert Enum.at(result.blocks, 0).work_report_hashes == %{Hash.two() => Hash.zero()}

      # Verify that the newest block was added (i.e., the block with work_report_hashes == [<<9::hash()>>])
      assert Enum.at(result.blocks, -1).work_report_hashes == %{<<9::hash()>> => Hash.five()}
    end

    test "correctly links inputs to MMR and work_package_hashes" do
      # Create a beefy commitment map
      accumulation_outputs =
        [
          %AccumulationOutput{service: 1, accumulated_output: <<11::hash()>>},
          %AccumulationOutput{service: 2, accumulated_output: <<22::hash()>>}
        ]

      # Create guarantees with specific work_package_hashes
      guarantee1 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.one(),
            exports_root: Hash.two()
          }
        }
      }

      guarantee2 = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.two(),
            exports_root: Hash.three()
          }
        }
      }

      # Call the function to update recent history
      result =
        RecentHistory.transition(
          %Header{},
          %RecentHistory{},
          [guarantee1, guarantee2],
          accumulation_outputs
        )

      # Verify that the MMR and work_package_hashes are correctly linked
      assert length(result.blocks) == 1

      assert Enum.at(result.blocks, -1).work_report_hashes == %{
               Hash.one() => Hash.two(),
               Hash.two() => Hash.three()
             }

      # Construct the expected Merkle tree root from the accumulation_outputs
      expected_merkle_root =
        accumulation_outputs
        |> Enum.map(fn %AccumulationOutput{service: service, accumulated_output: hash} ->
          <<service::service(), hash::binary>>
        end)
        |> MerkleTree.well_balanced_merkle_root(&Hash.keccak_256/1)

      # Verify that the beefy_root is based on the well-balanced Merkle root
      expected_mmr_roots = MMR.append(MMR.new(), expected_merkle_root).roots

      assert Enum.at(result.blocks, -1).beefy_root == expected_merkle_root
      assert result.beefy_belt == expected_mmr_roots
    end

    test "verifies state root is all zeros" do
      # Create a guarantee with specific work_package_hashes
      guarantee = %Guarantee{
        work_report: %Guarantee.WorkReport{
          specification: %AvailabilitySpecification{
            work_package_hash: Hash.one(),
            exports_root: Hash.two()
          }
        }
      }

      # Call the function to update recent history
      result =
        RecentHistory.transition(
          %Header{},
          %RecentHistory{},
          [guarantee],
          [%AccumulationOutput{service: 2, accumulated_output: Hash.five()}]
        )

      # Verify that the state root in the newly added block is all zeros
      assert Enum.at(result.blocks, -1).state_root == Hash.zero()
    end

    test "verifies header hash" do
      header = %Header{block_seal: Hash.one()}

      # Call the function to update recent history
      result =
        RecentHistory.transition(header, %RecentHistory{}, [], nil)

      # Verify that the state root in the newly added block is all zeros
      assert Enum.at(result.blocks, -1).header_hash == h(e(header))
    end
  end

  describe "encode/1" do
    test "encode recent history smoke test" do
      e(build(:recent_history))
    end
  end

  describe "decode/1" do
    test "decodes recent history " do
      recent_history = build(:recent_history)
      assert RecentHistory.decode(e(recent_history)) == {recent_history, <<>>}
    end
  end

  describe "get_well_balanced_merkle_root/1" do
    test "returns Hash.zero() for nil input" do
      assert RecentHistory.get_well_balanced_merkle_root(nil) == Hash.zero()
    end

    test "returns Hash.zero() for empty list" do
      assert RecentHistory.get_well_balanced_merkle_root([]) == Hash.zero()
    end

    test "calculates merkle root for non-empty MapSet" do
      map = [
        %AccumulationOutput{service: 1, accumulated_output: Hash.one()},
        %AccumulationOutput{service: 2, accumulated_output: Hash.two()}
      ]

      result = RecentHistory.get_well_balanced_merkle_root(map)
      refute result == Hash.zero()
    end
  end

  describe "from_json/1" do
    test "import json correctly" do
      json = JsonReader.read("test/system/state/recent_history.json")
      result = RecentHistory.from_json(json)
      assert %RecentHistory{blocks: [block1, block2], beefy_belt: beefy_belt} = result

      # Add assertions to verify the result
      assert block1 == %RecentBlock{
               header_hash:
                 <<0x530EF4636FEDD498E99C7601581271894A53E965E901E8FA49581E525F165DAE::hash()>>,
               beefy_root:
                 <<0x8720B97DDD6ACC0F6EB66E095524038675A4E4067ADC10EC39939EAEFC47D842::hash()>>,
               state_root:
                 <<0x1831DDE64E40BFD8639C2D122E5AC00FE133C48CD16E1621CA6D5CF0B8E10D3B::hash()>>,
               work_report_hashes: %{
                 <<0x016CB55EB7B84E0D495D40832C7238965BAEB468932C415DC2CEFFE0AFB039E5::hash()>> =>
                   <<0x935F6DFEF36FA06E10A9BA820F933611C05C06A207B07141FE8D87465870C11C::hash()>>,
                 <<0x76BCB24901299C331F0CA7342F4874F19B213EE72DF613D50699E7E25EDB82A6::hash()>> =>
                   <<0xC825D16B7325CA90287123BD149D47843C999CE686ED51EAF8592DD2759272E3::hash()>>
               }
             }

      # Check second block
      assert block2 == %RecentBlock{
               header_hash:
                 <<0x241D129C6EDC2114E6DFBA7D556F7F7C66399B55CEEC3078A53D44C752BA7E9A::hash()>>,
               beefy_root:
                 <<0x7076C31882A5953E097AEF8378969945E72807C4705E53A0C5AACC9176F0D56B::hash()>>,
               state_root:
                 <<0x0000000000000000000000000000000000000000000000000000000000000000::hash()>>,
               work_report_hashes: %{
                 <<0x3CC8D8C94E7B3EE01E678C63FD6B5DB894FC807DFF7FE10A11AB41E70194894D::hash()>> =>
                   <<0xC0EDFE377D20B9F4ED7D9DF9511EF904C87E24467364F0F7F75F20CFE90DD8FB::hash()>>
               }
             }

      assert beefy_belt ==
               [
                 nil,
                 <<0x8720B97DDD6ACC0F6EB66E095524038675A4E4067ADC10EC39939EAEFC47D842::hash()>>
               ]
    end
  end
end
