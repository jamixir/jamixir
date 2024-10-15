defmodule System.State.RecentHistory do
  @moduledoc """
  Manages a list of recent blocks, ensuring the max length is maintained.
  """

  alias Block.Header
  alias System.State.RecentHistory
  alias System.State.RecentHistory.RecentBlock
  alias Util.{Hash, MMR}

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
  @spec add(t(), Types.hash(), Types.hash(), list(Types.hash()), list(Types.hash())) :: t()
  def add(
        %__MODULE__{} = self,
        header_hash,
        state_root,
        accumulated_result_mmr,
        work_report_hashes
      ) do
    add(self, %RecentBlock{
      header_hash: header_hash,
      accumulated_result_mmr: accumulated_result_mmr,
      state_root: state_root,
      work_report_hashes: work_report_hashes
    })
  end

  @doc """
  Gets the initial block history, modifying the last block to include the given state root.
  Formula (82) v0.4.1
  """
  def update_latest_state_root_(nil, %Header{}) do
    __MODULE__.new()
  end

  @spec update_latest_state_root_(t(), Header.t()) :: t()
  def update_latest_state_root_(%__MODULE__{blocks: []} = self, %Header{}) do
    self
  end

  # β† ≡ β except β † [∣β∣ − 1]s = Hr
  def update_latest_state_root_(%__MODULE__{blocks: blocks} = self, %Header{
        prior_state_root: s
      }) do
    case Enum.split(blocks, length(blocks) - 1) do
      {init, [last_block]} ->
        %__MODULE__{self | blocks: init ++ [%RecentBlock{last_block | state_root: s}]}
    end
  end

  @doc """
  Adds a new block to the recent history.
  Formula (83) v0.4.1
  """
  def calculate_recent_history_(
        %Header{} = header,
        guarantees,
        %RecentHistory{} = recent_history,
        beefy_commitment_map
      ) do
    # 32 bytes of zeros
    state_root_ = Hash.zero()
    header_hash = Hash.default(Codec.Encoder.encode(header))

    # r - the merkle tree root of (service, commitment_hash) pairs derived from the beefy commitments map
    # Formula (83)
    well_balanced_merkle_root =
      case beefy_commitment_map do
        nil ->
          Hash.zero()

        [] ->
          Hash.zero()

        _ ->
          # The well-balanced merkle root of the beefy commitment map
          beefy_commitment_map.commitments
          |> (Enum.sort_by(&elem(&1, 0))
              |> Enum.map(fn {service, hash} ->
                encoded_index = Codec.Encoder.encode_little_endian(service, 4)
                <<encoded_index::binary, hash::binary>>
              end)
              |> Util.MerkleTree.well_balanced_merkle_root(&Hash.keccak_256/1))
      end

    # b - accumulated result mmr of the most recent block, appended with the well-balanced merkle root (r)
    # Formula (83) v0.4.1
    mmr_roots =
      case recent_history.blocks do
        [] ->
          MMR.append(MMR.new(), well_balanced_merkle_root).roots

        _ ->
          (recent_history.blocks
           |> Enum.map(& &1.accumulated_result_mmr)
           |> Enum.at(-1)
           |> MMR.from()
           |> MMR.append(well_balanced_merkle_root)).roots
      end

    # Work report hashes
    work_package_hashes =
      guarantees
      |> Enum.map(& &1.work_report.specification.work_package_hash)

    # Formula (84) v0.4.1
    RecentHistory.add(
      recent_history,
      header_hash,
      state_root_,
      mmr_roots,
      work_package_hashes
    )
  end

  defimpl Encodable do
    alias Codec.VariableSize
    # Formula (314) v0.4.1
    # C(3) ↦ E(↕[(h, EM (b), s, ↕p) ∣ (h, b, s, p) <− β])
    def encode(%RecentHistory{} = rh) do
      Codec.Encoder.encode(
        VariableSize.new(
          Enum.map(rh.blocks, fn b ->
            {
              b.header_hash,
              Codec.Encoder.encode_mmr(b.accumulated_result_mmr),
              b.state_root,
              VariableSize.new(b.work_report_hashes)
            }
          end)
        )
      )
    end
  end
end
