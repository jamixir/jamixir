defmodule NodeStateServerTest do
  alias Block.Extrinsic.Assurance
  alias Jamixir.Genesis
  alias System.State.Validator
  use ExUnit.Case, async: true
  use Jamixir.DBCase
  import Codec.Encoder
  import Jamixir.Factory
  import Jamixir.NodeStateServer
  import Mox

  setup do
    KeyManager.load_keys("test/keys/4.json")
    s = build(:genesis_state)
    Storage.put(Genesis.genesis_block_header(), s)
    start_link(jam_state: s)

    {:ok, state: s}
  end

  describe "validator index and assigned shards  " do
    test "returns nil no state found" do
      assert validator_index() == nil
    end

    test "returns nil when no index found" do
      assert validator_index() == nil
    end

    test "returns correct index", %{state: state} do
      assign_me_to_index(state, 3)
      assert validator_index() == 3
    end

    test "returns nil when not in validators list shard index" do
      assert assigned_shard_index(2) == nil
    end

    # i = (cR + v) mod V
    test "returns correct shard index", %{state: state} do
      assign_me_to_index(state, 2)
      # i = (1 * 2 + 2) mod 6 = 4
      assert assigned_shard_index(1) == 4
      # i = (0 * 2 + 2) mod 6 = 2
      assert assigned_shard_index(0) == 2
    end

    test "returns correct shard index overflow division", %{state: state} do
      assign_me_to_index(state, 5)
      # i = (1 * 2 + 5) mod 6 = 1
      assert assigned_shard_index(1) == 1
    end
  end

  describe "guarantors/0" do
    test "correctly return guarantors" do
      guarantors = guarantors()
      assert Enum.sort(guarantors.assigned_cores) == [0, 0, 0, 1, 1, 1]
      assert length(Enum.sort(guarantors.validators)) == 6
      [%Validator{} | _] = guarantors.validators
    end
  end

  describe "assigned_core/0" do
    test "returns assigned core for current validator", %{state: state} do
      assign_me_to_index(state, 1)
      assert assigned_core() in [0, 1]
    end

    test "returns nil when not a validator" do
      assert assigned_core() == nil
    end
  end

  describe "guarantors_same_core/0" do
    test "return other 2 guarantors in the same core", %{state: state} do
      assign_me_to_index(state, 1)
      guarantors = same_core_guarantors()
      assert length(guarantors) == 2

      assert Enum.find(guarantors, fn v -> v.ed25519 == KeyManager.get_our_ed25519_key() end) ==
               nil
    end
  end

  describe "current_timeslot/0" do
    test "returns current timeslot", %{state: state} do
      set_jam_state(put_in(state.timeslot, 5))
      assert current_timeslot() == 5
    end
  end

  describe "neightbours/0" do
    test "return my neightbours", %{state: state} do
      assign_me_to_index(state, 0)
      neighbours = neighbours()
      assert map_size(neighbours) == 2
      # I am not in my neightbours list
      assert Enum.find(neighbours, fn v -> v.ed25519 == KeyManager.get_our_ed25519_key() end) ==
               nil
    end
  end

  describe "fetch_work_report_shards/2" do
    setup %{state: state} do
      Application.put_env(:jamixir, :network_client, ClientMock)
      allow_db_access(Jamixir.NodeStateServer)
      set_mox_global()
      guarantee = build(:guarantee)
      wr = guarantee.work_report

      on_exit(fn ->
        Application.delete_env(:jamixir, :network_client)
      end)

      assign_me_to_index(state, 3)

      root = wr.specification.erasure_root

      pid = self()

      stub(ClientMock, :request_work_report_shard, fn ^pid, ^root, 3 ->
        {:ok, {<<1>>, [<<2>>, <<3>>], []}}
      end)

      {:ok, work_report: wr, root: root}
    end

    test "sends message to pid with fetched shards", %{work_report: wr, root: root} do
      :ok = fetch_work_report_shards(self(), wr)
      Process.sleep(40)
      assert Storage.get_segment_shard(root, 3, 0) == <<2>>
      assert Storage.get_segment_shard(root, 3, 1) == <<3>>
    end

    test "create new local assurance when fetching shards", %{work_report: wr} do
      :ok = fetch_work_report_shards(self(), wr)
      Process.sleep(40)

      [a] = Storage.get_assurances()
      assert a.hash == h(e(Genesis.genesis_block_header()))
      assert a.validator_index == 3
      <<b0::1, b1::1, _::6>> = a.bitfield
      assert b0 + b1 == 1

      if assigned_core() == 0 do
        assert b0 == 1
      else
        assert b1 == 1
      end
    end

    test "updates existing assurance when fetching shards", %{work_report: wr} do
      # assigns the other core to 1 and ours to 0
      bitfield =
        if assigned_core() == 0, do: <<0::1, 1::1, 0::6>>, else: <<1::1, 0::1, 0::6>>

      Storage.put(%Assurance{
        hash: h(e(Genesis.genesis_block_header())),
        validator_index: 3,
        bitfield: <<bitfield::b(bitfield)>>
      })

      :ok = fetch_work_report_shards(self(), wr)
      Process.sleep(40)

      [a] = Storage.get_assurances()
      assert a.hash == h(e(Genesis.genesis_block_header()))
      assert a.validator_index == 3
      <<b0::1, b1::1, _::6>> = a.bitfield
      assert b0 + b1 == 2
    end

    test "created assurance has valid signature", %{work_report: wr} do
      :ok = fetch_work_report_shards(self(), wr)
      Process.sleep(40)
      pub = KeyManager.get_our_ed25519_key()
      [a] = Storage.get_assurances()
      assert Assurance.verify_signature(a, pub)
    end
  end

  describe "handle_info assurance_timeout" do
    setup %{state: state} do
      Application.put_env(:jamixir, :connection_manager, ConnectionManagerMock)
      Application.put_env(:jamixir, :network_client, ClientMock)
      allow_db_access(Jamixir.NodeStateServer)
      set_mox_global()

      on_exit(fn ->
        Application.delete_env(:jamixir, :connection_manager)
        Application.delete_env(:jamixir, :network_client)
      end)

      assign_me_to_index(state, 3)
      {:ok, state: state}
    end

    test "distributes assurance to all connections when assurance exists", %{state: _state} do
      assurance =
        build(:assurance, hash: h(e(Genesis.genesis_block_header())), validator_index: 3)

      Storage.put(assurance)

      expect(ConnectionManagerMock, :get_connections, fn -> %{"k1" => "p1", "k2" => "p2"} end)
      expect(ClientMock, :distribute_assurance, fn "p1", ^assurance -> :ok end)
      expect(ClientMock, :distribute_assurance, fn "p2", ^assurance -> :ok end)

      send(Jamixir.NodeStateServer, {:clock, %{event: :assurance_timeout, slot: 1}})

      Process.sleep(50)
      verify!()
    end

    test "does not distribute when no assurance exists" do
      hash = h(e(Genesis.genesis_block_header()))
      assert Storage.get_assurance(hash, 3) == nil

      send(Jamixir.NodeStateServer, {:clock, %{event: :assurance_timeout, slot: 1}})

      Process.sleep(50)
      verify!()
    end
  end

  defp assign_me_to_index(state, index) do
    v = state.curr_validators |> Enum.at(index)
    v = put_in(v.ed25519, KeyManager.get_our_ed25519_key())
    new_curr = List.replace_at(state.curr_validators, index, v)
    s = put_in(state.curr_validators, new_curr)
    set_jam_state(s)
  end
end
