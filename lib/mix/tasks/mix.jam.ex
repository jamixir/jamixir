defmodule Mix.Tasks.Jam do
  use Mix.Task
  require Logger
  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"
  @switches [keys: :string, genesis: :string, port: :integer]

  def run(args) do
    Logger.info("🟣 Pump up the JAM, pump it up...")
    Logger.info("System loaded with config: #{inspect(Jamixir.config())}")
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    if keys_file = opts[:keys] do
      System.put_env("JAMIXIR_KEYS_FILE", keys_file)
    end

    if genesis_file = opts[:genesis] do
      System.put_env("JAMIXIR_GENESIS_FILE", genesis_file)
    end

    if port = opts[:port] do
      System.put_env("JAMIXIR_PORT", Integer.to_string(port))
    end

    Application.ensure_all_started(:jamixir)
    Process.sleep(:infinity)
  end
end
