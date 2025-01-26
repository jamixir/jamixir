defmodule KeyManager do
  @moduledoc """
  Manages the retrieval of public and private keys.
  """
  require Logger
  import Util.Hex
  @private_key_file "private_key.enc"

  @doc """
  Returns the public key as a binary.
  """
  @spec get_public_key() :: binary
  def get_public_key do
    {:ok, public_key_base64} = System.fetch_env("PUBLIC_KEY")
    Base.decode64!(public_key_base64)
  end

  @doc """
  Returns a tuple of {secret, public} keys, both as binaries.
  """
  @spec get_private_key() :: {binary, binary}
  def get_private_key do
    private_key_file = System.get_env("PRIVATE_KEY_FILE", @private_key_file)
    encrypted_private_key = File.read!(private_key_file)
    {:ok, password} = System.fetch_env("KEYSTORE_PASSWORD")

    decrypted_private_key = decrypt_private_key(encrypted_private_key, password)
    public_key = get_public_key()

    {decrypted_private_key, public_key}
  end

  @doc """
  Returns a tuple of {secret, public} keys as a keypair, both as binaries.
  This is an alias for get_private_key/0 for consistency with the rust implementation.
  """
  def get_keypair do
    {private_key, public_key} = get_private_key()
    {{private_key, public_key}, public_key}
  end

  defp decrypt_private_key(encrypted_data, password) do
    <<iv::binary-size(16), ciphertext::binary>> = encrypted_data
    key = :crypto.hash(:sha256, password) |> binary_part(0, 32)
    :crypto.crypto_one_time(:aes_256_cbc, key, iv, ciphertext, false)
  end

  def load_keys(%{bandersnatch: _, bandersnatch_priv: _} = keys) do
    Application.put_env(:jamixir, :keys, keys)
  end

  def load_keys(keys_file) do
    with {:ok, content} <- File.read(keys_file),
         {:ok, keys} <- Jason.decode(content) do
      # Store in application env
      keys = keys |> Utils.atomize_keys() |> JsonDecoder.from_json()
      Application.put_env(:jamixir, :keys, keys)
      Logger.info("🔑 Keys loaded successfully from #{keys_file}")
      Logger.info("🔑 Validator bandersnatch key: #{inspect(encode16(keys.bandersnatch))}")
      Logger.info("🔑 Validator ed25519 key: #{inspect(encode16(keys.ed25519))}")
      {:ok, keys}
    else
      {:error, e} ->
        Logger.error("Failed to load keys: #{inspect(e)}")
        {:error, e}
    end
  end
end
