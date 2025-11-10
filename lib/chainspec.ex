defmodule Jamixir.ChainSpec do
  @moduledoc """
  JIP-4 Chain Specification support for JAM.

  This module handles loading, converting, and working with JIP-4 chain specification files.

  Chain spec format:
  ```json
  {
    "id": "testnet",
    "bootnodes": ["evysk4p...@192.168.50.18:62061"],
    "genesis_header": "1ee155ace9c...",
    "genesis_state": {
      "01000...": "08b647...",
      ...
    },
    "protocol_parameters": "0a0000..."
  }
  ```
  """

  alias Codec.State
  alias Codec.State.Trie
  alias Jamixir.Genesis
  alias Util.Logger
  import Codec.Encoder
  import Util.Hex

  @type chainspec :: %{
          id: String.t(),
          bootnodes: list(String.t()),
          genesis_header: String.t(),
          genesis_state: %{String.t() => String.t()},
          protocol_parameters: String.t()
        }

  @doc """
  Load a chain spec from a JIP-4 JSON file.
  """
  @spec from_file(String.t()) :: {:ok, chainspec()} | {:error, term()}
  def from_file(file) do
    case File.read(file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json_data} ->
            {:ok, Utils.atomize_keys(json_data)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to read chain spec file: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Convert the current genesis.json and genesis_header.json to JIP-4 chain spec format.
  """
  @spec from_genesis(String.t() | nil, String.t() | nil) ::
          {:ok, chainspec()} | {:error, term()}
  def from_genesis(genesis_file \\ nil, header_file \\ nil) do
    genesis_file = genesis_file || Genesis.default_file()
    header_file = header_file || Genesis.header_file()

    with {:ok, state} <- State.from_file(genesis_file),
         {:ok, header} <- load_header_from_file(header_file) do
      # State -> Trie -> hex map (without 0x prefix per JIP-4)
      genesis_state_map = Trie.serialize_hex(state, prefix: false) |> Utils.atomize_keys()

      # Header -> encode -> hex (without 0x prefix per JIP-4)
      genesis_header_hex = encode16(e(header), prefix: false)

      chainspec = %{
        id: Application.get_env(:jamixir, :chain_id, "jamixir-devnet"),
        bootnodes: [],
        genesis_header: genesis_header_hex,
        genesis_state: genesis_state_map,
        protocol_parameters: encode_protocol_parameters()
      }

      {:ok, chainspec}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_header_from_file(header_file) do
    # Reuse existing code path
    header = JsonReader.read(header_file) |> Block.Header.from_json()
    {:ok, header}
  rescue
    e ->
      Logger.error("Failed to load header from #{header_file}: #{inspect(e)}")
      {:error, :invalid_header_file}
  end

  defp encode_protocol_parameters do
    # TODO: Implement proper protocol parameters encoding from Constants
    "0a00000000000000010000000000000064000000000000000200004b00000c000000809698000000000080f0fa020000000000ca9a3b00000000002d310100000000080000001000080003004038000003000800060050000400000080000500060000fa0000017cd20000093d0004000000000c00000204000000c0000080000000000c00000a000000"
  end

  @doc """
  Write a chain spec to a file in JIP-4 format.
  """
  @spec to_file(chainspec(), String.t()) :: :ok | {:error, term()}
  def to_file(chainspec, file) do
    case Jason.encode(chainspec, pretty: true) do
      {:ok, json} ->
        File.write(file, json)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Load genesis state from a JIP-4 chain spec into System.State.
  """
  @spec get_state(chainspec()) :: {:ok, System.State.t()} | {:error, term()}
  def get_state(%{genesis_state: genesis_state}) do
    # JIP-4 format is hex without 0x prefix
    # Convert to binary map, then use existing trie_to_state
    binary_map =
      for {key, value} <- genesis_state, into: %{} do
        # JsonDecoder expects 0x prefix, so add it
        key_bin = JsonDecoder.from_json(Atom.to_string(key))
        value_bin = JsonDecoder.from_json(value)
        {key_bin, value_bin}
      end

    # Use existing trie_to_state
    state = Trie.trie_to_state(binary_map)
    {:ok, state}
  end

  @doc """
  Load genesis header from a JIP-4 chain spec.
  """
  @spec get_header(chainspec()) :: {:ok, Block.Header.t()} | {:error, term()}
  def get_header(%{genesis_header: genesis_header_hex}) do
    # JIP-4 format is hex without 0x prefix, decode and use existing decoder
    header_binary = decode16!(genesis_header_hex)
    {header, _rest} = Block.Header.decode(header_binary)
    {:ok, header}
  rescue
    e ->
      Logger.error("Failed to decode genesis header: #{inspect(e)}")
      {:error, :invalid_genesis_header}
  end

  @doc """
  Parse a bootnode string in the format: <name>@<ip>:<port>
  where <name> is 53-char DNS name (e followed by base32 encoded ed25519 public key)
  """
  @spec parse_bootnode(String.t()) ::
          {:ok, %{name: String.t(), ip: String.t(), port: integer()}} | {:error, term()}
  def parse_bootnode(bootnode_str) do
    case String.split(bootnode_str, "@") do
      [name, ip_port] ->
        case String.split(ip_port, ":") do
          [ip, port] ->
            case Integer.parse(port) do
              {port_num, ""} ->
                {:ok, %{name: name, ip: ip, port: port_num}}

              _ ->
                {:error, :invalid_port}
            end

          _ ->
            {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Get bootnodes from a chain spec.
  """
  @spec get_bootnodes(chainspec()) :: list(%{name: String.t(), ip: String.t(), port: integer()})
  def get_bootnodes(%{bootnodes: bootnodes}) do
    bootnodes
    |> Enum.map(&parse_bootnode/1)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, node} -> node end)
  end
end
