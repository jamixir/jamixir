defmodule Mix.Tasks.Jam do
  use Mix.Task
  require Logger
  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"
  @switches [keys: :string]

  def run(args) do
    Logger.info("🟣 Pump up the JAM, pump it up...")
    {opts, _, _} = OptionParser.parse(args, strict: @switches)

    if keys_file = opts[:keys] do
      load_keys(keys_file)
    end

    Application.ensure_all_started(:jamixir)
    Process.sleep(:infinity)
  end

  defp load_keys(keys_file) do
    with {:ok, content} <- File.read(keys_file),
         keys <- Jason.decode!(content) |> Utils.atomize_keys() do
      # Store in application env
      keys = JsonDecoder.from_json(keys)
      Application.put_env(:jamixir, :keys, keys)
      Logger.info("🔑 Keys loaded successfully from #{keys_file}")
      {:ok, keys}
    else
      error ->
        Logger.error("Failed to load keys: #{inspect(error)}")
        {:error, error}
    end
  end
end
