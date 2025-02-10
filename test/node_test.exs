defmodule Jamixir.NodeTest do
  use ExUnit.Case
  alias Storage
  import Jamixir.Factory
  import TestHelper
  @genesis_file "genesis/genesis.json"

  setup do
    Application.put_env(:jamixir, :original_modules, [Jamixir.Node])
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    mock_header_seal()

    on_exit(fn ->
      Storage.remove_all()
      Application.delete_env(:jamixir, :original_modules)
      Application.delete_env(:jamixir, :header_seal)
    end)
  end

  test "inspect_state with empty state" do
    Storage.remove("state")
    assert {:ok, :no_state} = Jamixir.Node.inspect_state()
  end

  test "load_state from file" do
    assert :ok = Jamixir.Node.load_state(@genesis_file)
    assert {:ok, _keys} = Jamixir.Node.inspect_state()
  end

  test "add_block with valid block" do
    assert :ok = Jamixir.Node.load_state(@genesis_file)
    parent = build(:decodable_header)
    Storage.put(parent)
    block = build(:block)
    block_binary = Encodable.encode(block)

    assert {:ok, _} = Jamixir.Node.add_block(block_binary)
  end
end
