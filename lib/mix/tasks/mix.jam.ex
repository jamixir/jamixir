defmodule Mix.Tasks.Jam do
  use Mix.Task

  @shortdoc "Overrides the default `mix run` to start Jamixir.CLI"

  def run(_args) do
    # Set CARGO_MANIFEST_DIR environment variable
    manifest_dir = Path.expand("./native/bandersnatch_ring_vrf", Mix.Project.app_path())
    System.put_env("CARGO_MANIFEST_DIR", manifest_dir)
    IO.puts("CARGO_MANIFEST_DIR set to #{manifest_dir}")
    Jamixir.CLI.start()
  end
end
