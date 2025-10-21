defmodule Jamixir.NodeTest do
  use ExUnit.Case
  alias Block.Extrinsic.TicketProof
  alias Jamixir.Genesis
  alias Storage
  alias System.State.SealKeyTicket
  alias Util.Hash
  import Jamixir.Factory
  import TestHelper
  import Codec.Encoder
  import Jamixir.Node
  import Mox
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
    assert {:error, :no_state} = inspect_state(@genesis_hash)
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

  describe "save and get assurance" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Jamixir.Repo)
    end

    test "save_assurance with valid assurance" do
      assurance = build(:assurance)
      assert {:ok, _} = save_assurance(assurance)
      assert [assurance] == Storage.get_assurances()
    end
  end

  describe "save and get work package" do
    test "save_work_package with valid work package" do
      {wp, extrinsics} = work_package_and_its_extrinsic_factory()
      assert {:error, :execution_failed} = save_work_package(wp, 7, List.flatten(extrinsics))

      assert Storage.get_work_package(7) == wp
      assert Storage.get_work_package(5) == nil
    end

    test "save_work_package with invalid extrinsics" do
      wp = build(:work_package)
      {:error, :mismatched_extrinsics} = save_work_package(wp, 7, [<<1, 2, 3>>])
      {:error, :mismatched_extrinsics} = save_work_package(wp, 7, [])
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
    setup do
      Application.put_env(:jamixir, :connection_manager, ConnectionManagerMock)
      Application.put_env(:jamixir, :network_client, ClientMock)

      on_exit(fn ->
        Application.delete_env(:jamixir, :connection_manager)
        Application.delete_env(:jamixir, :network_client)
      end)

      %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)

      {:ok,
       epochs: for(_ <- 1..2, do: :rand.uniform(100_000)), state: state, key_pairs: key_pairs}
    end

    test "forward valid tickets", %{state: state, key_pairs: key_pairs} do
      state = %{state | entropy_pool: %{state.entropy_pool | n2: state.entropy_pool.n1}}
      Storage.put(Genesis.genesis_block_header(), state)

      {proof, _} = TicketProof.create_valid_proof(state, List.first(key_pairs), 0, 0)
      t1 = build(:ticket_proof, signature: proof, attempt: 0)

      invalid_t2 = build(:ticket_proof, attempt: 1)

      stub(ConnectionManagerMock, :get_connections, fn -> %{"k1" => 101, "k2" => 102} end)

      expect(ClientMock, :distribute_ticket, fn 101, :validator, 123, ^t1 -> :ok end)
      expect(ClientMock, :distribute_ticket, fn 102, :validator, 123, ^t1 -> :ok end)

      process_ticket(:proxy, 123, t1)
      process_ticket(:proxy, 123, invalid_t2)
      assert Storage.get_tickets(123) == [t1]
      verify!()
    end

    test "do not forward duplicated ticket", %{state: state, key_pairs: key_pairs} do
      state = %{state | entropy_pool: %{state.entropy_pool | n2: state.entropy_pool.n1}}
      Storage.put(Genesis.genesis_block_header(), state)

      {proof1, _} = TicketProof.create_valid_proof(state, List.first(key_pairs), 0, 0)
      {proof2, _} = TicketProof.create_valid_proof(state, List.first(key_pairs), 0, 1)
      t1 = build(:ticket_proof, signature: proof1, attempt: 0)
      t2 = build(:ticket_proof, signature: proof2, attempt: 1)
      # duplicated ticket
      t3 = build(:ticket_proof, signature: proof2, attempt: 1)

      stub(ConnectionManagerMock, :get_connections, fn -> %{"k1" => 101, "k2" => 102} end)

      expect(ClientMock, :distribute_ticket, fn 101, :validator, 123, ^t1 -> :ok end)
      expect(ClientMock, :distribute_ticket, fn 102, :validator, 123, ^t1 -> :ok end)
      expect(ClientMock, :distribute_ticket, fn 101, :validator, 123, ^t2 -> :ok end)
      expect(ClientMock, :distribute_ticket, fn 102, :validator, 123, ^t2 -> :ok end)

      process_ticket(:proxy, 123, t1)
      process_ticket(:proxy, 123, t2)
      process_ticket(:proxy, 123, t3)
      assert Storage.get_tickets(123) == [t1, t2]
      verify!()
    end

    test "do not forward ticket already in safrole state", %{state: state, key_pairs: key_pairs} do
      {proof1, _} = TicketProof.create_valid_proof(state, List.first(key_pairs), 0, 0)
      t1 = build(:ticket_proof, signature: proof1, attempt: 0)

      {:ok, output} =
        TicketProof.proof_output(t1, state.entropy_pool.n2, state.safrole.epoch_root)

      state = %{
        state
        | safrole: %{state.safrole | ticket_accumulator: [%SealKeyTicket{attempt: 0, id: output}]}
      }

      Storage.put(Genesis.genesis_block_header(), state)

      process_ticket(:proxy, 123, t1)
      assert Storage.get_tickets(123) == []
      verify!()
    end

    test "process_ticket with :validator mode", %{epochs: [e1, e2]} do
      [t1, t2] = build_list(2, :ticket_proof, attempt: 0)
      process_ticket(:validator, e1, t1)
      process_ticket(:validator, e2, t2)
      assert Storage.get_tickets(e1) == [t1]
      assert Storage.get_tickets(e2) == [t2]
    end
  end

  describe "save_judgement/3" do
    setup do
      Application.put_env(:jamixir, :node_state_server, NodeStateServerMock)
      Application.put_env(:jamixir, :network_client, ClientMock)

      on_exit(fn ->
        Application.delete_env(:jamixir, :node_state_server)
        Application.delete_env(:jamixir, :network_client)
      end)

      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Jamixir.Repo)

      {:ok, epochs: for(_ <- 1..2, do: :rand.uniform(100_000))}
    end

    test "save judgement locally for later block inclusion" do
      hash = Hash.random()
      j1 = build(:judgement, vote: true)
      j2 = build(:judgement, vote: true, validator_index: 2)
      save_judgement(1, hash, j1)
      save_judgement(1, hash, j2)
      save_judgement(2, Hash.random(), build(:judgement, vote: true))
      assert Storage.get_judgements(1) == [j1, j2]
      assert Storage.get_judgements(2) |> length() == 1
    end

    test "distribute judgement to neighbours" do
      hash = Hash.random()
      judgment = build(:judgement, vote: false)

      neighbours = [{"validator1", 101}, {"validator2", 102}]

      stub(NodeStateServerMock, :neighbours, fn -> neighbours end)

      expect(ClientMock, :announce_judgement, fn 101, 1, ^hash, ^judgment -> :ok end)
      expect(ClientMock, :announce_judgement, fn 102, 1, ^hash, ^judgment -> :ok end)

      save_judgement(1, hash, judgment)

      verify!()
    end

    test "don't distribute judgement to neighbours if it is positive" do
      save_judgement(1, Hash.one(), build(:judgement, vote: true))
    end
  end
end
