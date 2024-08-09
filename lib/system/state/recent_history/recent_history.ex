defmodule System.State.RecentHistory do
  @moduledoc """
  Manages a list of recent blocks, ensuring the max length is maintained.
  """

  alias System.State.{RecentHistory, BeefyCommitmentMap}
  alias System.State.RecentHistory.RecentBlock
  alias Block.Header
  alias Util.{Hash, MMR}
  alias Block.Extrinsic.Guarantee

  @max_length 8

  @type t :: %__MODULE__{
          blocks: list(RecentBlock.t())
        }

  defstruct blocks: []

  @doc """
  Initializes a RecentBlocks struct.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{blocks: []}
  end

  @doc """
  Adds a new RecentBlock to the list, ensuring the max length is maintained.
  """
  def add(%__MODULE__{blocks: blocks} = self, %RecentBlock{} = new_block) do
    updated_blocks = (blocks ++ [new_block]) |> Enum.take(-@max_length)
    %__MODULE__{self | blocks: updated_blocks}
  end

  @doc """
  Creates a new RecentBlock and adds it to the list, ensuring the max length is maintained.
  """
  @spec add(
          t(),
          Types.hash(),
          Types.hash(),
          list(Types.hash()),
          list(Types.hash())
        ) :: t()
  def add(
        %__MODULE__{} = self,
        header_hash,
        state_root,
        accumulated_result_mmr,
        work_report_hashes
      ) do
    new_block = %RecentBlock{
      header_hash: header_hash,
      accumulated_result_mmr: accumulated_result_mmr,
      state_root: state_root,
      work_report_hashes: work_report_hashes
    }

    add(self, new_block)
  end

  @doc """
  Gets the initial block history, modifying the last block to include the given state root.
  """
  def update_latest_posterior_state_root(nil, %Header{
        prior_state_root: _s
      }) do
    __MODULE__.new()
  end

  @spec update_latest_posterior_state_root(t(), Header.t()) :: t()
  def update_latest_posterior_state_root(%__MODULE__{blocks: blocks} = self, %Header{
        prior_state_root: _s
      })
      when length(blocks) == 0 do
    self
  end

  def update_latest_posterior_state_root(%__MODULE__{blocks: blocks} = self, %Header{
        prior_state_root: s
      }) do
    case Enum.split(blocks, length(blocks) - 1) do
      {init, [last_block]} ->
        modified_last_block = %RecentBlock{last_block | state_root: s}
        %__MODULE__{self | blocks: init ++ [modified_last_block]}
    end
  end

  def posterior_recent_history(
        header,
        guarantees,
        %RecentHistory{} = recent_history,
        beefy_commitment_map
      ) do
    # 32 bytes of zeros
    posterior_state_root = <<0::256>>
    header_hash = Hash.blake2b_256("header")

    # r - the merkle tree root of (service_index, commitment_hash) pairs derived from the beefy commitments map
    # equation (83)
    well_balanced_merkle_root =
      case beefy_commitment_map do
        nil ->
          <<0::256>>

        [] ->
          <<0::256>>

        _ ->
          # The well-balanced merkle root of the beefy commitment map
          beefy_commitment_map.commitments
          |> (Enum.sort_by(&elem(&1, 0))
              |> Enum.map(fn {service_index, hash} ->
                encoded_index = ScaleEncoding.encode_integer(service_index)
                <<encoded_index::binary, hash::binary>>
              end)
              |> Util.MerkleTree.well_balanced_merkle_root(&Hash.keccak_256/1))
      end

    # b - acuumaleted result mmr of the most recent block, appended with the well-balanced merkle root (r)
    # equation (83)
    mmr_roots =
      case recent_history.blocks do
        [] ->
          MMR.new()
          |> MMR.append(well_balanced_merkle_root)
          |> MMR.roots()

        _ ->
          recent_history.blocks
          |> Enum.map(& &1.accumulated_result_mmr)
          |> Enum.at(-1)
          |> MMR.from()
          |> MMR.append(well_balanced_merkle_root)
          |> MMR.roots()
      end

    # Work report hashes
    work_package_hashes =
      guarantees
      |> Enum.map(& &1.work_report.specfication.work_package_hash)

    RecentHistory.add(
      recent_history,
      header_hash,
      posterior_state_root,
      mmr_roots,
      work_package_hashes
    )
  end
end
