defmodule Jamixir.CLI do
  def start do
    IO.puts("Starting Jamixir...")
    Storage.start_link()
    Jamixir.TCPServer.start(4000)
  end

  require Logger

  @private_key_file "private_key.enc"

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

  # Main CLI function to generate keypair, encrypt, and store in env vars
  def generate_keypair do
    {private_key_tuple, public_key} = RingVrf.generate_secret_from_rand()

    private_key = elem(private_key_tuple, 0)

    encoded_public_key = Base.encode64(public_key)
    File.write!(".env", "PUBLIC_KEY=#{encoded_public_key}\n", [:append])

    password = prompt_password()

    {:ok, encrypted_key} = encrypt_private_key(private_key, password)

    File.write!(@private_key_file, encrypted_key)

    if !File.exists?(@private_key_file) do
      Logger.error("Failed to create encrypted private key file at #{@private_key_file}")
    end

    File.write!(".env", "KEYSTORE_PASSWORD=#{password}\n", [:append])

    Logger.info("Public key and password stored in env vars, and private key encrypted.")
  end
end
