defmodule System.State.RecentHistory do
  @moduledoc """
  Manages a list of recent blocks, ensuring the max length is maintained.
  """

  alias System.State.RecentBlock
  alias Block.Header

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
end
