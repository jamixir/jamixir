defmodule Codec.State do

  alias Codec.State.Json
  use Codec.Encoder



  def from_genesis(file \\ "genesis.json") do
    case File.read(file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json_data} ->
            {:ok, Json.decode(json_data |> Utils.atomize_keys())}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end


end
