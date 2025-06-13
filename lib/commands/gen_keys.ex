defmodule Jamixir.Commands.GenKeys do
  @moduledoc """
  Generate a new secret key seed and print the derived session keys
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [file_name: :string, help: :boolean],
        aliases: [h: :help]
      )

    if opts[:help] do
      print_help()
    else
      # Pass options to the CLI function
      cli_opts = if opts[:file_name], do: [file_name: opts[:file_name]], else: []
      Jamixir.CLI.generate_keypair(cli_opts)
    end
  end

  defp print_help do
    IO.puts("""
    Generate a new secret key seed and print the derived session keys

    Usage: jamixir gen-keys [OPTIONS]

    Options:
        --file-name <FILE_NAME>  Secret key seed file name. If not specified, a file name containing the current time will be generated
    -h, --help                   Print help
    """)
  end
end
