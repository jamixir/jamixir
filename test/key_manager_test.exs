defmodule KeyManagerTest do
  alias Util.Hash
  use ExUnit.Case

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
end
