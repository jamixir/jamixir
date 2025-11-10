defmodule Jamixir.Commands.GenChainspec do
  @moduledoc """
  Generate a JIP-4 chain specification file from genesis.json
  """
  alias Jamixir.ChainSpec
  alias Util.Logger

  @switches [
    output: :string,
    genesis: :string,
    header: :string,
    chain_id: :string,
    help: :boolean
  ]

  @aliases [
    o: :output,
    g: :genesis,
    h: :help
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if opts[:help] do
      print_help()
    else
      generate_chainspec(opts)
    end
  end

  defp generate_chainspec(opts) do
    output = opts[:output] || "chainspec.json"
    genesis_file = opts[:genesis]
    header_file = opts[:header]

    # Set chain_id if provided
    if chain_id = opts[:chain_id] do
      Application.put_env(:jamixir, :chain_id, chain_id)
    end

    Logger.info("🔗 Generating JIP-4 chain specification...")

    case ChainSpec.from_genesis(genesis_file, header_file) do
      {:ok, chainspec} ->
        case ChainSpec.to_file(chainspec, output) do
          :ok ->
            Logger.info("✅ Chain specification written to: #{output}")
            Logger.info("📋 Chain ID: #{chainspec.id}")
            Logger.info("📦 Genesis header: #{String.slice(chainspec.genesis_header, 0..31)}...")

            Logger.info(
              "📊 Genesis state entries: #{Map.keys(chainspec.genesis_state) |> length()}"
            )

            :ok

          {:error, reason} ->
            Logger.error("❌ Failed to write chain spec file: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        Logger.error("❌ Failed to generate chain spec: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp print_help do
    IO.puts("""
    Generate a JIP-4 chain specification file from genesis.json

    Usage: jamixir gen-chainspec [OPTIONS]

    Options:
      -o, --output <FILE>         Output chain spec file (default: chainspec.json)
      -g, --genesis <FILE>        Genesis state file (default: priv/genesis.json)
          --header <FILE>         Genesis header file (default: priv/genesis_header.json)
          --chain-id <ID>         Chain identifier (default: jamixir-devnet)
      -h, --help                  Print help

    Examples:
      jamixir gen-chainspec
      jamixir gen-chainspec --output my-chain.json --chain-id testnet
      jamixir gen-chainspec --genesis ./custom-genesis.json --output chainspec.json
    """)
  end
end
