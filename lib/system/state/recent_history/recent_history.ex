defmodule System.State.RecentHistory do
  @moduledoc """
  Manages a list of recent blocks, ensuring the max length is maintained.
  """

  alias Block.Header
  alias System.State.RecentHistory
  alias System.State.RecentHistory.RecentBlock
  alias Util.{Hash, MMR}
  use Codec.Encoder
  use SelectiveMock

  @max_length Constants.recent_history_size()

  @type t :: %__MODULE__{
          blocks: list(RecentBlock.t())
        }

  defstruct blocks: []

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
  @spec add(t(), Types.hash(), Types.hash(), list(Types.hash()), %{Types.hash() => Types.hash()}) ::
          t()
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

  mockable(calculate_header_hash(header), do: h(e(header)))

  # when we want to have a provided header hash, we take the value from header extrinsic_hash
  def mock(:calculate_header_hash, context), do: context[:header].extrinsic_hash
  def mock(:get_well_balanced_merkle_root, context), do: context[:beefy_commitment]
  def mock(:transition, context), do: context[:recent_history]

  @doc """
  Gets the initial block history, modifying the last block to include the given state root.
  Formula (7.2) v0.6.0
  """
  def update_latest_state_root(nil, _), do: %__MODULE__{}

  @spec update_latest_state_root(t(), Types.hash()) :: t()
  def update_latest_state_root(%__MODULE__{blocks: []} = self, _), do: self

  # β† ≡ β except β † [∣β∣ − 1]s = Hr
  def update_latest_state_root(%__MODULE__{blocks: blocks} = self, prior_state_root) do
    case Enum.split(blocks, length(blocks) - 1) do
      {init, [last_block]} ->
        %__MODULE__{
          self
          | blocks: init ++ [%RecentBlock{last_block | state_root: prior_state_root}]
        }
    end
  end

  @doc """
  Adds a new block to the recent history.
  Formula (7.3) v0.6.0
  """
  mockable transition(
             %Header{prior_state_root: prior_state_root} = header,
             %RecentHistory{} = recent_history,
             guarantees,
             beefy_commitment
           ) do
    # β† Formula (4.6) v0.6.0
    recent_history =
      RecentHistory.update_latest_state_root(recent_history, prior_state_root)

    # 32 bytes of zeros
    state_root_ = Hash.zero()
    header_hash = calculate_header_hash(header)

    # r - the merkle tree root of (service, commitment_hash) pairs derived from the beefy commitments map
    # Formula (7.3) v0.6.0

    well_balanced_merkle_root = get_well_balanced_merkle_root(beefy_commitment)

    # b - accumulated result mmr of the most recent block, appended with the well-balanced merkle root (r)
    # Formula (7.3) v0.6.0

    mmr_roots =
      case recent_history.blocks do
        [] ->
          MMR.append(MMR.new(), well_balanced_merkle_root, &Hash.keccak_256/1).roots

        _ ->
          (for(b <- recent_history.blocks, do: b.accumulated_result_mmr)
           |> Enum.at(-1)
           |> MMR.from()
           |> MMR.append(well_balanced_merkle_root, &Hash.keccak_256/1)).roots
      end

    # Work report hashes
    wp_hashes =
      for g <- guarantees,
          spec = g.work_report.specification,
          do: {spec.work_package_hash, spec.exports_root},
          into: %{}

    # Formula (7.4) v0.6.0
    RecentHistory.add(recent_history, header_hash, state_root_, mmr_roots, wp_hashes)
  end

  mockable get_well_balanced_merkle_root(beefy_commitment) do
    case beefy_commitment do
      nil ->
        Hash.zero()

      %MapSet{} = map ->
        if MapSet.size(map) == 0 do
          Hash.zero()
        else
          prepare_commitments(map)
          |> Util.MerkleTree.well_balanced_merkle_root(&Hash.keccak_256/1)
        end
    end
  end

  def prepare_commitments(map) do
    MapSet.to_list(map)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {service, hash} ->
      <<e_le(service, 4)::binary, hash::binary>>
    end)
  end

  defimpl Encodable do
    use Codec.Encoder
    # Formula (D.2) v0.6.0
    # C(3) ↦ E(↕[(h, EM (b), s, ↕p) ∣ (h, b, s, p) <− β])
    def encode(%RecentHistory{} = rh) do
      e(
        vs(
          for b <- rh.blocks do
            {b.header_hash, Codec.Encoder.encode_mmr(b.accumulated_result_mmr), b.state_root,
             vs(b.work_report_hashes)}
          end
        )
      )
    end
  end

  def from_json(json_data) do
    case json_data do
      nil -> %RecentHistory{}
      _ -> %RecentHistory{blocks: for(b <- json_data, do: RecentBlock.from_json(b))}
    end
  end

  def to_json_mapping do
    %{
      # nil key means use the value as root
      blocks: :_root
    }
  end
end
