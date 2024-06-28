defmodule Jamixir.CLI do
  def start do
    IO.puts "Starting Jamixir..."
    Jamixir.TCPServer.start(4000)
  end
end