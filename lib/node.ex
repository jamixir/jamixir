defmodule Jamixir.Node do
  def add_block(block_binary) when is_binary(block_binary) do
    with {block, _rest} <- Block.decode(block_binary),
         app_state <- Storage.get_state() do
      case System.State.add_block(app_state, block) do
        {:ok, new_app_state} ->
          Storage.put(new_app_state)
          Storage.put(block.header)
          :ok
        {:error, _pre_state, reason} ->
          {:error, reason}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def inspect_state do
    case Storage.get_state() do
      nil -> {:ok, :no_state}
      state -> {:ok, Map.keys(state)}
    end
  end

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
            state = System.State.from_json(json_data |> Utils.atomize_keys())
            Storage.put(state)
            :ok
          error -> error
        end
      error -> error
    end
  end
end
