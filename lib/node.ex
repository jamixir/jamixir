defmodule Jamixir.Node do
  alias System.State
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
          Storage.put(block.header)
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
    case Storage.get_state() do
      nil ->
        {:error, :no_state}

      state ->
        key_atom = String.to_existing_atom(key)

        case Map.fetch(state, key_atom) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, :key_not_found}
        end
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
            error
        end

      error ->
        error
    end
  end

  @impl true
  def add_ticket(_epoch, _attempt, _proof) do
    {:error, :not_implemented}
  end

  @impl true
  def add_work_package(_core, _wp, _extrinsic) do
    {:error, :not_implemented}
  end

  @impl true
  def get_blocks(_hash, _order, _count) do
    {:error, :not_implemented}
  end

  @impl true
  def receive_preimage(_service_id, _hash, _length) do
    {:error, :not_implemented}
  end

  @impl true
  def get_preimage(_hash) do
    {:error, :not_implemented}
  end

  @impl true
  def save_preimage(_preimage) do
    {:error, :not_implemented}
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
  def save_guarantee(_guarantee) do
    {:error, :not_implemented}
  end

  @impl true
  def get_work_report(_hash) do
    {:error, :not_implemented}
  end

  @impl true
  def save_work_package(_wp, _core, _extrinsic) do
    {:error, :not_implemented}
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
end
