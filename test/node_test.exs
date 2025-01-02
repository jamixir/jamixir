defmodule Jamixir.NodeTest do
  use ExUnit.Case
  alias Storage
  alias Util.Hash
  import Jamixir.Factory

  setup do
    # Clean everything
    :mnesia.stop()
    :mnesia.delete_schema([node()])

    # Start fresh
    {:ok, _} = Storage.start_link()

    # Clear any existing state
    # Storage.put_state(nil)
    :ok
  end

  test "inspect_state with empty state" do
    assert {:ok, :no_state} = Jamixir.Node.inspect_state()
  end

  test "load_state from file" do
    assert :ok = Jamixir.Node.load_state("genesis.json")
    assert {:ok, _keys} = Jamixir.Node.inspect_state()
  end

  @tag :skip
  test "add_block with valid block" do
    assert :ok = Jamixir.Node.load_state("genesis.json")
    parent = build(:decodable_header)
    parent_hash = Hash.default(Encodable.encode(parent))
    Storage.put(parent)
    block = build(:block)
    block = put_in(block.header.parent_hash, parent_hash)
    block_binary = Encodable.encode(block)

    assert :ok = Jamixir.Node.add_block(block_binary)
  end
end
