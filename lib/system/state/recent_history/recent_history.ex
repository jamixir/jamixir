defmodule System.State.RecentHistory do
  @moduledoc """
  Manages a list of recent blocks, ensuring the max length is maintained.
  """

  alias Block.Extrinsic.Guarantee
  alias Block.Header
  alias System.State.RecentHistory
  alias System.State.RecentHistory.{Lastaccout, RecentBlock}
  alias Util.{Hash, MMR}
  import Codec.{Encoder, Decoder}

  import Util.MerkleTree
  import Util.Hash, only: [keccak_256: 1, zero: 0]
  alias Codec.VariableSize
  use SelectiveMock

  @max_length Constants.recent_history_size()

  @type t :: %__MODULE__{blocks: list(RecentBlock.t()), beefy_belt: list(Types.hash() | nil)}

  defstruct blocks: [], beefy_belt: []

  @doc """
  Adds a new RecentBlock to the list, ensuring the max length is maintained.
  """
  def add(%__MODULE__{blocks: blocks} = self, %RecentBlock{} = new_block) do
    updated_blocks = (blocks ++ [new_block]) |> Enum.take(-@max_length)
    %__MODULE__{self | blocks: updated_blocks}
  end

  mockable(calculate_header_hash(header), do: h(e(header)))

  # when we want to have a provided header hash, we take the value from header extrinsic_hash
  def mock(:calculate_header_hash, context), do: context[:header].extrinsic_hash
  def mock(:get_well_balanced_merkle_root, context), do: context[:lastaccout]
  def mock(:transition, context), do: context[:recent_history]

  @doc """
  Formula (7.5) v0.6.7
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
  Formula (7.8) v0.6.7
  """
  @spec transition(Header.t(), t(), list(Guarantee.t()), list(Lastaccout.t())) :: t()
  mockable transition(
             %Header{prior_state_root: prior_state_root} = header,
             %RecentHistory{beefy_belt: beefy_belt} = recent_history,
             guarantees,
             lastaccouts
           ) do
    # β† Formula (4.6) v0.6.6
    recent_history =
      RecentHistory.update_latest_state_root(recent_history, prior_state_root)

    # 32 bytes of zeros
    state_root_ = zero()
    header_hash = calculate_header_hash(header)

    # Formula (7.6) v0.6.7
    merkle_root = get_well_balanced_merkle_root(lastaccouts)

    # Formula (7.7) v0.6.7
    beefy_belt_ =
      MMR.from(beefy_belt)
      |> MMR.append(merkle_root, &keccak_256/1)
      |> MMR.to_list()

    # Formula (7.8) v0.6.7
    wp_hashes =
      for g <- guarantees,
          spec = g.work_report.specification,
          do: {spec.work_package_hash, spec.exports_root},
          into: %{}

    new_block = %RecentBlock{
      header_hash: header_hash,
      beefy_root: super_peak_mmr(beefy_belt_),
      state_root: state_root_,
      work_report_hashes: wp_hashes
    }

    RecentHistory.add(recent_history, new_block) |> Map.put(:beefy_belt, beefy_belt_)
  end

  mockable get_well_balanced_merkle_root(lastaccouts) do
    case lastaccouts do
      nil ->
        Hash.zero()

      [] ->
        Hash.zero()

      _ ->
        # Formula (7.6) v0.6.7
        s =
          for %Lastaccout{service: service, accumulated_output: h} <- lastaccouts,
              do: <<service::service(), h::binary>>

        well_balanced_merkle_root(s, &keccak_256/1)
    end
  end

  defimpl Encodable do
    import Codec.Encoder, only: [encode_mmr: 1, e: 1, vs: 1]
    # Formula (D.2) v0.6.7
    # C(3) ↦ E(↕[(h, b, s, ↕p) S⎧ ⎩h, b, s, p⎫ ⎭<− βH ], EM (βB ))
    def encode(%RecentHistory{} = rh) do
      e(
        {vs(
           for b <- rh.blocks do
             {b.header_hash, b.accumulated_result_mmb, b.state_root, e(b.work_report_hashes)}
           end
         ), encode_mmr(rh.beefy_belt)}
      )
    end
  end

  def decode(bin) do
    {blocks, rest} = VariableSize.decode(bin, &RecentBlock.decode/1)
    {beefy_belt, rest} = decode_mmr(rest)
    {%__MODULE__{blocks: blocks, beefy_belt: beefy_belt}, rest}
  end

  def from_json(json_data) do
    case json_data do
      nil ->
        %RecentHistory{}

      [] ->
        %RecentHistory{}

      _ ->
        %RecentHistory{
          blocks: for(b <- json_data.history, do: RecentBlock.from_json(b)),
          beefy_belt: json_data.mmr.peaks |> JsonDecoder.from_json()
        }
    end
  end

  def to_json_mapping do
    %{
      # nil key means use the value as root
      blocks: :_root
    }
  end
end
