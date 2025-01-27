defmodule Mix.Tasks.Jam do
  use Mix.Task
  require Logger
  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"
  @switches [keys: :string, genesis: :string]

  def run(args) do
    Logger.info("🟣 Pump up the JAM, pump it up...")
    Logger.info("System loaded with config: #{inspect(Jamixir.config())}")
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    if keys_file = opts[:keys] do
      KeyManager.load_keys(keys_file)
    end

    if genesis_file = opts[:genesis] do
      Application.put_env(:jamixir, :genesis_file, genesis_file)
    end

    Application.ensure_all_started(:jamixir)
    Process.sleep(:infinity)
  end
end
