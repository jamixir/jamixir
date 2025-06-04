defmodule Codec.State do
  alias Codec.State.Json
  require Logger

  def from_file(file) do
    case File.read(file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json_data} ->
            {:ok, Json.decode(json_data |> Utils.atomize_keys())}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(reason)
        {:error, reason}
    end
  end

  def from_genesis(file \\ "genesis/genesis.json") do
    from_file(file)
  end
end
