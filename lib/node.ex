defmodule Jamixir.Node do
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Block.Extrinsic.WorkPackage
  alias Util.Hash
  alias System.State
  alias Util.Hash
  use StoragePrefix
  import Util.Hex, only: [b16: 1]
  require Logger

  @behaviour Jamixir.NodeAPI

  @impl true
  def add_block(block_binary) when is_binary(block_binary) do
    {block, _} = Block.decode(block_binary)
    add_block(block)
  end

  def add_block(%Block{} = block) do
    with app_state <- Storage.get_state() do
      case State.add_block(app_state, block) do
        {:ok, new_app_state} ->
          Storage.put(new_app_state)
          Storage.put(block)
          Logger.info("🔄 State Updated successfully")
          Logger.debug("🔄 New State: #{inspect(new_app_state)}")
          {:ok, new_app_state}

        {:error, _pre_state, reason} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def inspect_state do
    case Storage.get_state() do
      nil -> {:ok, :no_state}
      state -> {:ok, Map.keys(state)}
    end
  end

  @impl true
  @spec inspect_state(any()) :: {:error, :key_not_found | :no_state} | {:ok, any()}
  def inspect_state(key) do
    case Storage.get_state(key) do
      nil ->
        {:error, :no_state}

      value ->
        {:ok, value}
    end
  end

  def load_state(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, json_data} ->
            state = Codec.State.Json.decode(json_data |> Utils.atomize_keys())
            Storage.put(state)
            :ok

          error ->
            {:error, error}
        end

      error ->
        {:error, error}
    end
  end

  @impl true
  def add_ticket(_epoch, _attempt, _proof) do
    {:error, :not_implemented}
  end

  # CE 128 - Block Request
  @impl true
  def get_blocks(_, _, 0), do: {:ok, []}

  def get_blocks(header_hash, :descending, count) do
    {blocks, _} =
      Enum.reduce_while(1..count, {[], header_hash}, fn _, {blocks, next_hash} ->
        case Storage.get_block(next_hash) do
          nil ->
            {:halt, {blocks, nil}}

          block ->
            {:cont, {blocks ++ [block], block.header.parent_hash}}
        end
      end)

    {:ok, blocks}
  end

  def get_blocks(header_hash, :ascending, count) do
    {blocks, _} =
      Enum.reduce_while(1..count, {[], header_hash}, fn _, {blocks, next_hash} ->
        case Storage.get("#{@p_child}#{next_hash}") do
          nil ->
            {:halt, {blocks, nil}}

          child_hash ->
            case Storage.get_block(child_hash) do
              nil ->
                {:halt, {blocks, nil}}

              block ->
                next_hash = Hash.default(Encodable.encode(block.header))
                {:cont, {[block | blocks], next_hash}}
            end
        end
      end)

    {:ok, Enum.reverse(blocks)}
  end

  # CE 142 - Preimage Announcement
  @impl true
  def receive_preimage(_service_id, hash, _length) do
    server_pid = self()

    Task.start(fn ->
      Logger.info(
        "Requesting preimage #{b16(hash)} back from client via server #{inspect(server_pid)}"
      )

      Network.Connection.get_preimage(server_pid, hash)
    end)

    :ok
  end

  # CE 143 - Preimage Request
  @impl true
  def get_preimage(hash) do
    case Storage.get("#{@p_preimage}#{hash}") do
      nil ->
        {:error, :not_found}

      preimage ->
        {:ok, preimage}
    end
  end

  @impl true
  def save_preimage(preimage) do
    Storage.put("#{@p_preimage}#{Hash.default(preimage)}", preimage)
    :ok
  end

  @impl true
  def save_assurance(_assurance) do
    {:error, :not_implemented}
  end

  @impl true
  def process_ticket(:proxy = _mode, _epoch, _ticket) do
    {:error, :not_implemented}
  end

  def process_ticket(:validator = _mode, _epoch, _ticket) do
    {:error, :not_implemented}
  end

  @impl true
  def save_judgement(_epoch, _hash, _judgement) do
    {:error, :not_implemented}
  end

  @impl true
  def save_guarantee(guarantee) do
    spec = guarantee.work_report.specification
    Logger.info("Saving guarantee for work report: #{b16(spec.work_package_hash)}")
    Storage.put("#{@p_guarantee}#{spec.work_package_hash}", guarantee)

    server_pid = self()

    case Storage.get_state() do
      nil ->
        Logger.error("No state found to request erasure code for work report")
        {:error, :no_state}

      state ->
        Task.start(fn ->
          Logger.info("Request EC  for work report: #{b16(spec.work_package_hash)}")

          Network.Connection.request_audit_shard(
            server_pid,
            spec.erasure_root,
            my_assigned_shard_index(state, guarantee.work_report.core_index)
          )
        end)
    end

    :ok
  end

  @impl true
  def get_work_report(hash) do
    case Storage.get("#{@p_guarantee}#{hash}") do
      nil -> {:error, :not_found}
      guarantee -> {:ok, guarantee.work_report}
    end
  end

  @impl true
  @spec save_work_package(Block.Extrinsic.WorkPackage.t(), integer(), list(binary())) ::
          :ok | {:error, :invalid_extrinsics}
  def save_work_package(wp, core, extrinsics) do
    if WorkPackage.valid_extrinsics?(wp, extrinsics) do
      Storage.put(wp, core)

      for e <- extrinsics do
        Storage.put(e)
      end

      process_work_package(wp, core, extrinsics)

      :ok
    else
      Logger.error("Invalid extrinsics for work package service #{wp.service} core #{core}")
      {:error, :invalid_extrinsics}
    end
  end

  def process_work_package(wp, core, extrinsics) do
    Logger.info("Processing work package for service #{wp.service} core #{core}")

    state = Storage.get_state()

    # A work-package received via CE 133 should be shared with the other guarantors
    # assigned to the core using this protocol, but only after:

    # It has been determined that it is possible to generate a work-report that could be included
    # on chain. This will involve, for example, verifying the WP's authorization.
    # All import segments have been retrieved. Note that this will involve mapping any WP
    # hashes in the import list to segments-roots.

    # TODO verify imports before executing the work package.
    # The refine logic need not be executed before sharing a work-package;
    # ideally, refinement should be done while waiting for the other guarantors to respond.
    case WorkReport.execute_work_package(wp, core, state.services) do
      :error ->
        Logger.error("Failed to execute work package for service #{wp.service} core #{core}")
        {:error, :execution_failed}

      task ->
        {_work_report, _exports} = Task.await(task, :infinity)
        Logger.info("Work package executed successfully, saving work report")

        # TODO
        # 1 - erasure code exports and save for upcoming calls
        # 2 - distribute Guarantee to other validators
        :ok
    end
  end

  @impl true
  def save_work_package_bundle(_bundle, _core, _segments) do
    {:error, :not_implemented}
  end

  @impl true
  def save_audit(_audit) do
    {:error, :not_implemented}
  end

  @impl true
  def get_segment(_erasure_root, _segment_index) do
    {:error, :not_implemented}
  end

  @impl true
  def get_segment_shards(_erasure_root, _segment_index, _share_index) do
    {:error, :not_implemented}
  end

  @impl true
  def get_state_trie(_header_hash) do
    {:error, :not_implemented}
  end

  @impl true
  def get_justification(_erasure_root, _segment_index, _shard_index) do
    {:error, :not_implemented}
  end

  def my_validator_index(nil), do: nil

  def my_validator_index(state) do
    state.curr_validators
    |> Enum.find_index(fn v -> v.ed25519 == KeyManager.get_our_ed25519_key() end)
  end

  # i = (cR + v) mod V
  def my_assigned_shard_index(state, core) do
    case my_validator_index(state) do
      nil ->
        nil

      v ->
        rem(core * Constants.erasure_code_recovery_threshold() + v, Constants.validator_count())
    end
  end
end
