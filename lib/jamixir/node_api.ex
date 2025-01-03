defmodule Jamixir.NodeAPI do
  alias Block.Extrinsic.WorkPackage
  @callback add_block(binary) :: :ok | {:error, any}
  @callback inspect_state() :: {:ok, any} | {:error, any}
  @callback inspect_state(any()) :: {:error, :key_not_found | :no_state} | {:ok, any()}

  @callback get_blocks(Types.hash(), :asc | :desc, integer()) ::
              {:ok, list(Block.t())} | {:error, any}
  # CE 131/132 Safrole ticket distribution (epoch index, attempt, proof)
  @callback add_ticket(
              Types.epoch_index(),
              integer(),
              Types.bandersnatch_ringVRF_proof_of_knowledge()
            ) :: :ok | {:error, any}
  # CE 133 - Work-package submission (core index, WP, extrinsic data)
  @callback add_work_package(integer(), WorkPackage.t(), binary()) :: :ok | {:error, any}

  def add_block(a), do: impl().add_block(a)
  def inspect_state, do: impl().inspect_state()
  def inspect_state(a), do: impl().inspect_state(a)
  def get_blocks(hash, order, count), do: impl().get_blocks(hash, order, count)
  def add_ticket(epoch, attempt, proof), do: impl().add_ticket(epoch, attempt, proof)
  def add_work_package(core, wp, extrinsic), do: impl().add_work_package(core, wp, extrinsic)

  defp impl, do: Application.get_env(:jamixir, NodeAPI, Jamixir.Node)
end
