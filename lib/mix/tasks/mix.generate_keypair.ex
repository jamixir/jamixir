defmodule Mix.Tasks.GenerateKeypair do
  use Mix.Task
  require Logger

  @shortdoc "Generates a bandersnatch keypair and stores private key in file and public key in .env"

  def run(_args) do
    Jamixir.CLI.generate_keypair()
  end
end
