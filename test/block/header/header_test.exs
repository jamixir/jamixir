defmodule Block.HeaderTest do
  use ExUnit.Case
  import Codec.Encoder
  import TestHelper
  import Jamixir.Factory

  alias Block.Extrinsic
  alias Block.Header
  alias Codec.NilDiscriminator
  alias System.State
  alias Util.Hash
  import TestHelper

  describe "validate_parent/1" do
    test "validate_parent/1 returns true when parent_hash is nil and timeslot is 0" do
      header = build(:decodable_header, parent_hash: nil, timeslot: 0)
      assert Header.validate_parent(header) == :ok
    end

    test "valid_parent/1 returns error when parent header is not found" do
      header = %Header{parent_hash: "parent_hash", timeslot: past_timeslot()}

      assert Header.validate_parent(header) == {:error, :no_parent}
    end

    test "valid_parent/1 returns error when timeslot is not greater than parent header's timeslot" do
      parent = build(:decodable_header, timeslot: 1)

      header =
        build(:decodable_header, parent_hash: Hash.default(Encodable.encode(parent)), timeslot: 1)

      Storage.put(parent)

      assert Header.validate_parent(header) == {:error, :invalid_parent_timeslot}
    end
  end

  describe "valid_extrinsic_hash?/2" do
    test "valid_extrinsic_hash?/2 wrong hash" do
      extrinsic = build(:extrinsic)
      header = %Header{extrinsic_hash: "other"}
      assert !Header.valid_extrinsic_hash?(header, extrinsic)
    end

    test "valid_extrinsic_hash?/2 correct" do
      extrinsic = build(:extrinsic)
      header = %Header{extrinsic_hash: Extrinsic.calculate_hash(extrinsic)}
      assert Header.valid_extrinsic_hash?(header, extrinsic)
    end
  end

  setup do
    {:ok, header: %Header{block_seal: <<123::hash()>>}}
  end

  # Formula (C.22) v0.7.2
  describe "encode/1" do
    test "encode header smoke test" do
      assert Encodable.encode(build(:header))
    end

    test "encode header", %{header: header} do
      assert Encodable.encode(header) ==
               Header.unsigned_encode(header) <> e(header.block_seal)
    end
  end

  describe "decode/1" do
    setup do
      {:ok, header: build(:decodable_header)}
    end

    test "decode header smoke test", %{header: header} do
      encoded = Encodable.encode(header)
      {decoded, _} = Header.decode(encoded)
      assert decoded == header
    end

    test "unsigned decode header will all fields", %{header: header} do
      header = put_in(header.block_seal, nil)
      encoded = Header.unsigned_encode(header)
      {decoded, _} = Header.unsigned_decode(encoded)
      assert decoded == header
    end
  end

  describe "validate/2" do
    setup do
      state = %State{timeslot: 99}
      state_root = Codec.State.Trie.state_root(state)
      parent = build(:decodable_header, timeslot: 99)
      Storage.put(parent)

      {:ok,
       header: %Header{timeslot: 100, prior_state_root: state_root, parent_hash: h(e(parent))},
       state: state}
    end

    test "returns :ok when all conditions are met", %{header: header, state: state} do
      assert Header.validate(header, state) == :ok
    end

    test "returns error when header timeslot is not greater than state timeslot", %{state: state} do
      header = %Header{timeslot: 99}
      assert {:error, _reason} = Header.validate(header, state)
    end

    test "returns error when block time is in the future" do
      time = future_timeslot()
      header = %Header{timeslot: time}
      state = %State{timeslot: time - 1}

      assert {:error, message} = Header.validate(header, state)
      assert String.starts_with?(message, "Invalid block time: block_time")
    end

    test "returns error when state root is invalid", %{state: state, header: header} do
      header = put_in(header.prior_state_root, Hash.zero())
      assert {:error, message} = Header.validate(header, state)
      assert String.starts_with?(message, "Invalid state root.")
    end
  end

  # Formula (C.23) v0.7.2
  describe "unsigned_encode/1" do
    test "unsigned_encode header", %{header: h} do
      assert Header.unsigned_encode(h) ==
               e({h.parent_hash, h.prior_state_root, h.extrinsic_hash}) <>
                 e_le(h.timeslot, 4) <>
                 e(
                   {NilDiscriminator.new(h.epoch_mark),
                    NilDiscriminator.new(h.winning_tickets_marker), vs(h.offenders_marker),
                    e_le(h.block_author_key_index, 2), h.vrf_signature}
                 )
    end
  end

  describe "ancestors/1" do
    test "ancestors for nil is empty" do
      assert Header.ancestors(nil) == []
    end

    test "ancestors returns empty list when parent_header is nil" do
      header = %Header{parent_hash: nil}
      assert Enum.take(Header.ancestors(header), 1) == [header]
    end

    test "ancestors returns parent header when parent header is found" do
      grandparent = build(:decodable_header)
      parent = build(:decodable_header, parent_hash: h(e(grandparent)))
      header = build(:decodable_header, parent_hash: h(e(parent)))
      Storage.put([grandparent, parent, header])

      assert Enum.take(Header.ancestors(header), 3) == [header, parent, grandparent]
    end
  end
end
