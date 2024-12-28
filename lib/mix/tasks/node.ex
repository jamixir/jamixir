defmodule Mix.Tasks.Node do
  use Mix.Task
  @shortdoc "Manage the Jamixir node"

  def run(["start"]) do
    # Start the node in detached mode using elixir --detached
    System.cmd("elixir", [
      "--name", "jamixir_node@127.0.0.1",
      "--erl", "-detached",
      "-S", "mix", "run", "--no-halt"
    ])

    # Give it a moment to start up
    Process.sleep(1000)
    IO.puts("Jamixir node started successfully.")
  end

  def run(["stop"]) do
    rpc_call(Jamixir.Node, :stop, [])
  end

  def run(["inspect", key]) do
    rpc_call(Jamixir.Node, :inspect_state, [key])
  end

  def run(["inspect"]) do
    rpc_call(Jamixir.Node, :inspect_state, [])
  end

  def run(["load", file]) do
    rpc_call(Jamixir.Node, :load_state, [file])
  end

  def run(["save", file]) do
    rpc_call(Jamixir.Node, :save_state, [file])
  end

  def run(["add", block]) do
    rpc_call(Jamixir.Node, :add_block, [block])
  end

  def run(_) do
    print_usage()
  end

  defp rpc_call(module, function, args) when is_list(args) do
    Node.start(:"command_client@127.0.0.1", :longnames)

    unless Node.connect(:"jamixir_node@127.0.0.1") do
      IO.puts("Error: Could not connect to :jamixir_node@127.0.0.1")
      exit(:normal)
    end

    case :rpc.call(:"jamixir_node@127.0.0.1", module, function, args) do
      {:badrpc, reason} ->
        IO.puts("Error: #{inspect(reason)}")
      {:ok, response} ->
        IO.puts(inspect(response, pretty: true))
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
      response ->
        IO.puts(inspect(response, pretty: true))
    end
  end

  defp print_usage do
    IO.puts("""
    Usage:
      mix node start              # Start the Jamixir node
      mix node stop              # Stop the node
      mix node load <file>       # Load state from JSON file
      mix node save <file>       # Save state to JSON file
      mix node add <block>       # Add a block
      mix node inspect [key]     # Inspect state (optionally with key)
    """)
  end
end
