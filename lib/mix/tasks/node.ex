defmodule Mix.Tasks.Node do
  use Mix.Task
  require Logger
  @shortdoc "Manage the Jamixir node"

  @node_name :"jamixir@127.0.0.1"
  @cookie :jamixir_cookie

  def run(["start" | extra_args]) do
    args = ["--name", "#{@node_name}", "--cookie", "#{@cookie}", "-S", "mix", "jam"]

    # Start the node in detached mode
    MuonTrap.cmd(
      "elixir",
      args ++ extra_args,
      cd: File.cwd!(),
      into: IO.stream(:stdio, :line)
    )
  end

  def run(["stop" | _]) do
    connect_and_call(:init, :stop, [])
  end

  def run(["inspect"]) do
    connect_and_call(Jamixir.NodeCLIServer, :inspect_state, [])
    |> handle_response()
  end

  def run(["inspect", key]) do
    connect_and_call(Jamixir.NodeCLIServer, :inspect_state, [key])
    |> handle_response()
  end

  def run(["load", file]) do
    connect_and_call(Jamixir.NodeCLIServer, :load_state, [file])
    |> handle_response()
  end

  defp connect_and_call(module, function, args) do
    # Start our own node for the CLI
    Node.start(:"cli@127.0.0.1", :longnames)
    Node.set_cookie(@cookie)

    case Node.connect(@node_name) do
      true ->
        :rpc.call(@node_name, module, function, args)

      false ->
        {:error, :node_not_available}
    end
  end

  # credo:disable-for-next-line
  defp handle_response({:ok, response}), do: IO.inspect(response, label: "Response")
  defp handle_response({:error, reason}), do: IO.puts("Error: #{inspect(reason)}")
  # credo:disable-for-next-line
  defp handle_response(other), do: IO.inspect(other, label: "Response")

  def print_usage do
    IO.puts("""
    Usage:
      mix node start              # Start the Jamixir node
      mix node stop              # Stop the node
      mix node load <file>       # Load state from JSON file
      mix node inspect [key]     # Inspect state (optionally with key)
    """)
  end
end
