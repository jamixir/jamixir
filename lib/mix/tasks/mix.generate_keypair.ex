defmodule Mix.Tasks.GenerateKeypair do
  use Mix.Task
  require Logger

  @shortdoc "Generates a bandersnatch keypair and stores private key in file and public key in .env"

  def run(args) do
    # Reuse the same logic as the release command
    Jamixir.Commands.GenKeys.run(args)
  end
end
