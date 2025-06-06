defmodule Jamixir.NodeTest do
  use ExUnit.Case
  alias Util.Hash
  alias Storage
  import Jamixir.Factory
  import TestHelper
  use Codec.Encoder
  import Jamixir.Node

  @genesis_file "genesis/genesis.json"
  setup_validators(1)

  setup do
    Application.put_env(:jamixir, :original_modules, [Jamixir.Node])
    Application.put_env(:jamixir, :header_seal, HeaderSealMock)
    mock_header_seal()

    on_exit(fn ->
      Storage.remove_all()
      Application.delete_env(:jamixir, :original_modules)
      Application.delete_env(:jamixir, :header_seal)
    end)

    :ok = load_state(@genesis_file)
  end

  test "inspect_state with empty state" do
    Storage.remove("state")
    assert {:ok, :no_state} = inspect_state()
  end

  test "load_state from file" do
    assert :ok = load_state(@genesis_file)
    assert {:ok, _keys} = inspect_state()
  end

  describe "add_block" do
    test "add_block with valid block bin" do
      block = build(:block)
      assert {:ok, _} = add_block(e(block))
    end
  end

  alias Block.Extrinsic

  describe "get_blocks/3" do
    test "get_blocks with empty storage" do
      assert {:ok, []} = get_blocks(Hash.random(), :ascending, 0)
    end

    test "get_blocks with invalid hash" do
      assert {:ok, []} = get_blocks(Hash.random(), :descending, 3)
      assert {:ok, []} = get_blocks(Hash.random(), :ascending, 3)
    end

    test "get_blocks descending with valid block hash" do
      block1 = %Block{build(:decodable_block) | extrinsic: %Extrinsic{}}

      block2 = %Block{
        build(:decodable_block, parent_hash: h(e(block1.header)))
        | extrinsic: %Extrinsic{}
      }

      {:ok, _} = add_block(block1)
      {:ok, _} = add_block(block2)

      # one block fetch
      {:ok, [b]} = get_blocks(h(e(block2.header)), :descending, 1)
      assert b == block2

      # two blocks fetch
      {:ok, [b2, b1]} = get_blocks(h(e(block2.header)), :descending, 2)
      assert b2 == block2
      assert b1 == block1

      # fetch more than available blocks
      {:ok, blocks} = get_blocks(h(e(block2.header)), :descending, 10)
      assert length(blocks) == 2
    end

    test "get_blocks ascending with valid block hash" do
      block1 = %Block{build(:decodable_block) | extrinsic: %Extrinsic{}}

      block2 = %Block{
        build(:decodable_block, parent_hash: h(e(block1.header)))
        | extrinsic: %Extrinsic{}
      }

      block3 = %Block{
        build(:decodable_block, parent_hash: h(e(block2.header)))
        | extrinsic: %Extrinsic{}
      }

      {:ok, _} = add_block(block1)
      {:ok, _} = add_block(block2)
      {:ok, _} = add_block(block3)

      # one block fetch
      {:ok, [b2]} = get_blocks(h(e(block1.header)), :ascending, 1)
      assert b2 == block2

      # two blocks fetch
      {:ok, [b2, b3]} = get_blocks(h(e(block1.header)), :ascending, 2)
      assert b2 == block2
      assert b3 == block3

      # fetch more than available blocks
      {:ok, blocks} = get_blocks(h(e(block1.header)), :ascending, 10)
      assert length(blocks) == 2
    end
  end
end
