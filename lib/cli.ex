defmodule Jamixir.CLI do
  alias Util.Logger

  @keys_dir Path.join([System.user_home(), "Library", "Application Support", "jamixir", "keys"])

  # Function to encrypt the private key using AES
  def encrypt_private_key(private_key, password) do
    key = :crypto.hash(:sha256, password) |> binary_part(0, 32)
    iv = :crypto.strong_rand_bytes(16)
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, key, iv, private_key, true)
    {:ok, iv <> ciphertext}
  end

  def prompt_password do
    password = IO.gets(:stdio, "Enter password to encrypt private key: ") |> String.trim()
    if password == "", do: prompt_password(), else: password
  end

  # Main CLI function to generate keypair, encrypt, and store in structured format
  def generate_keypair(opts \\ []) do
    {{private_key, _}, public_key} = RingVrf.generate_secret_from_rand()

    # Create keys directory if it doesn't exist
    File.mkdir_p!(@keys_dir)

    # Generate filename with timestamp or use provided filename
    filename =
      case opts[:file_name] do
        nil ->
          timestamp =
            DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(":", "-")

          "#{timestamp}.seed"

        name when is_binary(name) ->
          if String.ends_with?(name, ".seed"), do: name, else: "#{name}.seed"
      end

    seed_path = Path.join(@keys_dir, filename)

    # Create seed file content (you may want to adjust this format)
    seed_data = %{
      private_key: Base.encode64(private_key),
      public_key: Base.encode64(public_key),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    password = prompt_password()
    {:ok, encrypted_key} = encrypt_private_key(private_key, password)

    # Write encrypted seed file
    File.write!(seed_path, Jason.encode!(seed_data))

    # Also maintain backward compatibility with .env and private_key.enc
    encoded_public_key = Base.encode64(public_key)
    File.write!(".env", "PUBLIC_KEY=#{encoded_public_key}\n", [:append])
    File.write!("private_key.enc", encrypted_key)
    File.write!(".env", "KEYSTORE_PASSWORD=#{password}\n", [:append])

    Logger.info("Key pair generated and saved to #{seed_path}")
    Logger.info("Public key: #{encoded_public_key}")
    Logger.info("Seed file: #{seed_path}")
  end
end
