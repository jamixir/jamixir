defmodule NodeStateServerTest do
  alias Block.Extrinsic.Assurance
  alias Jamixir.Genesis
  alias Jamixir.NodeStateServer
  alias Storage.AvailabilityRecord
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

      stub(ClientMock, :request_work_package_shard, fn ^pid, ^root, 3 ->
        {:ok, {<<1>>, [<<2>>, <<3>>], []}}
      end)

      {:ok, work_report: wr, root: root}
    end

    test "sends message to pid with fetched shards", %{work_report: wr, root: root} do
      :ok = fetch_work_report_shards(self(), wr)
      Process.sleep(40)
      assert Storage.get_segment_shard(root, 3, 0) == <<2>>
      assert Storage.get_segment_shard(root, 3, 1) == <<3>>
      assert Storage.get_bundle_shard(wr.specification.work_package_hash, 3) == <<1>>
    end

    test "creates availability record when fetching shards", %{work_report: wr} do
      spec = wr.specification
      :ok = fetch_work_report_shards(self(), wr)
      Process.sleep(40)

      [ar] = Jamixir.Repo.all(AvailabilityRecord)
      assert ar.work_package_hash == spec.work_package_hash
      assert ar.bundle_length == spec.length
      assert ar.erasure_root == spec.erasure_root
      assert ar.exports_root == spec.exports_root
      assert ar.segment_count == spec.segment_count
      assert ar.shard_index == 3
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

      # base assurance for all tests
      assurance = %Assurance{
        hash: h(e(Genesis.genesis_block_header())),
        validator_index: 3,
        bitfield: <<0::8>>
      }

      {priv, _} = KeyManager.get_our_ed25519_keypair()

      state = assign_me_to_index(state, 3)
      {:ok, state: state, assurance: assurance, priv: priv}
    end

    test "doesnt distribute assurance when all bits are 0", %{state: state} do
      NodeStateServer.handle_info(
        {:clock, %{event: :assurance_timeout, slot: 1}},
        %{jam_state: state}
      )

      assert Storage.get_assurances() == []

      verify!()
    end

    test "assurance bit is set to 1 when is avaiable", %{
      state: state,
      assurance: assurance,
      priv: priv
    } do
      pid = self()

      cr = build(:core_report)
      state = %{state | core_reports: [nil, cr]}
      spec = cr.work_report.specification

      Storage.put(AvailabilityRecord.from_spec(spec, 3))

      assert Storage.get_availability(cr.work_report) != nil

      expected_assurance =
        %Assurance{assurance | bitfield: <<0b00000010>>}
        |> Assurance.signed(priv)

      expect(ConnectionManagerMock, :get_connections, fn -> %{"k1" => "p1", "k2" => "p2"} end)
      expect(ClientMock, :distribute_assurance, 2, fn p, a -> send(pid, {:distributed, p, a}) end)

      NodeStateServer.handle_info(
        {:clock, %{event: :assurance_timeout, slot: 1}},
        %{jam_state: state}
      )

      assert_receive {:distributed, pid1, ^expected_assurance}, 500
      assert_receive {:distributed, pid2, ^expected_assurance}, 500
      assert MapSet.new([pid1, pid2]) == MapSet.new(["p1", "p2"])

      # also checks that node store its own assurance
      [^expected_assurance] = Storage.get_assurances()

      verify!()
    end
  end

  defp assign_me_to_index(state, index) do
    v = state.curr_validators |> Enum.at(index)
    v = put_in(v.ed25519, KeyManager.get_our_ed25519_key())
    new_curr = List.replace_at(state.curr_validators, index, v)
    s = put_in(state.curr_validators, new_curr)
    set_jam_state(s)
    s
  end
end
