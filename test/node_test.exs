defmodule Jamixir.NodeTest do
  use ExUnit.Case
  alias Block.Extrinsic.TicketProof
  alias Util.Hash
  alias Storage
  import Jamixir.Factory
  import TestHelper
  import Codec.Encoder
  import Jamixir.Node
  alias Jamixir.Genesis
  use StoragePrefix

  @genesis_file Genesis.default_file()
  @genesis_hash Genesis.genesis_header_hash()
  @genesis_state_key @p_state <> @genesis_hash
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
    Storage.remove(@genesis_state_key)
    assert {:ok, :no_state} = inspect_state(@genesis_hash)
  end

  test "load_state from file" do
    assert :ok = load_state(@genesis_file)
    assert {:ok, _keys} = inspect_state(@genesis_hash)
  end

  describe "add_block" do
    test "add_block with valid block bin" do
      block = build(:block, header: build(:header, parent_hash: @genesis_hash))

      :ok = load_state(@genesis_file)

      assert {:ok, _, _} = add_block(block)
    end
  end

  describe "add_block_with_header/2" do
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
      block1 = build(:decodable_block, parent_hash: @genesis_hash, extrinsic: %Extrinsic{})

      block2 = %Block{
        build(:decodable_block, parent_hash: h(e(block1.header)))
        | extrinsic: %Extrinsic{}
      }

      {:ok, _, _} = add_block(block1)
      {:ok, _, _} = add_block(block2)

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
      block1 = build(:decodable_block, parent_hash: @genesis_hash, extrinsic: %Extrinsic{})

      block2 = %Block{
        build(:decodable_block, parent_hash: h(e(block1.header)))
        | extrinsic: %Extrinsic{}
      }

      block3 = %Block{
        build(:decodable_block, parent_hash: h(e(block2.header)))
        | extrinsic: %Extrinsic{}
      }

      {:ok, _, _} = add_block(block1)
      {:ok, _, _} = add_block(block2)
      {:ok, _, _} = add_block(block3)

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

  describe "get and save preimage" do
    test "get_preimage with empty storage" do
      assert {:error, :not_found} = get_preimage(Hash.random())
    end

    test "save and get preimage" do
      preimage = <<1, 2, 3, 4, 5>>
      assert :ok = save_preimage(preimage)
      assert {:ok, ^preimage} = get_preimage(Hash.default(preimage))
    end

    test "get_preimage with non-existing hash" do
      assert {:error, :not_found} = get_preimage(Hash.random())
    end
  end

  describe "save and get work package" do
    test "save_work_package with valid work package" do
      {wp, extrinsics} = work_package_and_its_extrinsic_factory()
      assert :ok = save_work_package(wp, 7, extrinsics)

      assert Storage.get_work_package(7) == wp
      assert Storage.get_work_package(5) == nil
    end

    test "save_work_package with invalid extrinsics" do
      wp = build(:work_package)
      {:error, :invalid_extrinsics} = save_work_package(wp, 7, [<<1, 2, 3>>])
      {:error, :invalid_extrinsics} = save_work_package(wp, 7, [])
    end
  end

  describe "distribute and get work report" do
    test "distribute_work_report guarantee with valid parameters" do
      guarantee = build(:guarantee)
      spec = guarantee.work_report.specification
      :ok = save_guarantee(guarantee)

      {:ok, r} = get_work_report(spec.work_package_hash)
      assert r == guarantee.work_report
    end

    test "request an unexisting work report" do
      assert {:error, :not_found} = get_work_report(Hash.random())
    end
  end

  describe "save_work_package_bundle/3" do
    test "save bundle returning validator signature" do
    end
  end

  describe "process_ticket/3" do
    test "process_ticket with :proxy mode" do
      process_ticket(:proxy, 1, %TicketProof{})
    end

    test "process_ticket with :validator mode" do
      assert {:error, :not_implemented} = process_ticket(:validator, 1, %{})
    end
  end
end
