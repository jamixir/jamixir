defmodule KeyManagerTest do
  alias Util.Hash
  use ExUnit.Case
  import Util.Hex

  setup_all do
    {:ok, private_key_file} = Temp.path(%{suffix: ".enc"})

    System.put_env("PUBLIC_KEY", Base.encode64("test_public_key"))
    System.put_env("KEYSTORE_PASSWORD", "test_password")
    System.put_env("PRIVATE_KEY_FILE", private_key_file)

    iv = :crypto.strong_rand_bytes(16)
    File.write!(private_key_file, iv <> Hash.random())

    on_exit(fn ->
      System.delete_env("PUBLIC_KEY")
      System.delete_env("KEYSTORE_PASSWORD")
      System.delete_env("PRIVATE_KEY_FILE")
    end)

    :ok
  end

  describe "KeyManager" do
    test "get_public_key/0" do
      assert KeyManager.get_public_key() == "test_public_key"
    end

    test "get_private_key/0 returns a tuple of binaries" do
      {private_key, public_key} = KeyManager.get_private_key()
      assert is_binary(private_key)
      assert is_binary(public_key)
      assert byte_size(private_key) == 32
    end

    test "get_keypair/0 " do
      {private_key, public_key} = KeyManager.get_keypair()
      assert private_key == KeyManager.get_private_key()
      assert public_key == KeyManager.get_public_key()
    end
  end

  @keys_file "priv/keys/0.json"

  describe "load_keys/1" do
    setup do
      on_exit(fn ->
        Application.delete_env(:jamixir, :keys)
      end)

      :ok
    end

    test "loads keys from valid JSON file" do
      KeyManager.load_keys(@keys_file)
      keys = Application.get_env(:jamixir, :keys)

      assert keys.ed25519 ==
               decode16!("0x4418fb8c85bb3985394a8c2756d3643457ce614546202a2f50b093d762499ace")

      assert keys.ed25519_priv ==
               decode16!("0x996542becdf1e78278dc795679c825faca2e9ed2bf101bf3c4a236d3ed79cf59")
    end

    test "handles missing file" do
      assert {:error, %File.Error{reason: :enoent, path: "nonexistent.json", action: "read file"}} =
               KeyManager.load_keys("nonexistent.json")
    end

    test "handles invalid JSON" do
      invalid_file = "priv/keys/invalid.json"
      File.write!(invalid_file, "invalid json")
      assert {:error, %Jason.DecodeError{}} = KeyManager.load_keys(invalid_file)
      File.rm!(invalid_file)
    end
  end
end
