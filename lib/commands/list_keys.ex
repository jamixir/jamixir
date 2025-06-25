defmodule Jamixir.Commands.ListKeys do
  @moduledoc """
  List all session keys we have the secret key for
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [help: :boolean],
        aliases: [h: :help]
      )

    if opts[:help] do
      print_help()
    else
      list_keys()
    end
  end

  defp list_keys do
    # Define the keys directory path similar to polkajam
    keys_dir =
      Path.join([System.user_home(), "Library", "Application Support", "jamixir", "keys"])

    case File.ls(keys_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".seed"))
        |> Enum.sort()
        |> Enum.each(&display_key_info/1)

      {:error, _} ->
        IO.puts("No keys directory found at #{keys_dir}")
    end
  end

  defp display_key_info(filename) do
    keys_dir =
      Path.join([System.user_home(), "Library", "Application Support", "jamixir", "keys"])

    file_path = Path.join(keys_dir, filename)

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"public_key" => public_key, "private_key" => _private_key}} ->
            # Generate peer ID from public key (you'll need to implement this based on your format)
            peer_id = generate_peer_id(public_key)
            IO.puts("#{file_path}: Peer ID: #{peer_id}")
            IO.puts("#{file_path}: Bandersnatch key: #{public_key |> String.slice(0, 64)}")

          {:error, _} ->
            IO.puts("#{file_path}: Invalid key file format")
        end

      {:error, _} ->
        IO.puts("#{file_path}: Error reading key file")
    end
  end

  # This should be implemented based on your peer ID generation logic
  defp generate_peer_id(public_key) do
    # Placeholder - implement based on your actual peer ID generation
    :crypto.hash(:sha256, Base.decode64!(public_key))
    |> Base.encode32(case: :lower, padding: false)
    |> String.slice(0, 53)
  end

  defp print_help do
    IO.puts("""
    List all session keys we have the secret key for

    Usage: jamixir list-keys

    Options:
    -h, --help  Print help
    """)
  end
end
