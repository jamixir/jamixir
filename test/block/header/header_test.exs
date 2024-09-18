defmodule Block.HeaderTest do
  use ExUnit.Case
  import TestHelper
  import Jamixir.Factory

  alias Block.Header
  alias System.State
  alias Codec.{NilDiscriminator, VariableSize}

  describe "valid_header?/1" do
    test "valid_header?/1 returns true when parent_hash is nil" do
      header = %Header{parent_hash: nil, timeslot: past_timeslot()}
      assert Header.valid_header?(Storage.new(), header)
    end

    test "valid_header?/1 returns false when parent header is not found" do
      header = %Header{parent_hash: "parent_hash", timeslot: past_timeslot()}

      assert !Header.valid_header?(Storage.new(), header)
    end

    test "valid_header?/1 returns false when timeslot is not greater than parent header's timeslot" do
      header = %Header{parent_hash: :parent, timeslot: 2}
      s1 = Storage.put(Storage.new(), :parent, %Header{timeslot: 1})
      s2 = Storage.put(s1, :header, header)

      assert Header.valid_header?(s2, header)
    end

    test "valid_header?/1 returns false when timeslot is in the future" do
      header = %Header{parent_hash: :parent, timeslot: 2}
      s1 = Storage.put(Storage.new(), :parent, %Header{timeslot: 3})
      s2 = Storage.put(s1, :header, header)

      assert !Header.valid_header?(s2, header)
    end

    test "valid_header?/1 returns false if timeslot is bigger now" do
      header = %Header{parent_hash: nil, timeslot: future_timeslot()}

      assert !Header.valid_header?(Storage.new(), header)
    end
  end

  setup do
    {:ok, header: %Header{block_seal: <<123::256>>}}
  end

  # Formula (281) v0.3.4
  describe "encode/1" do
    test "encode header smoke test" do
      assert Encodable.encode(build(:header))
    end

    test "encode header", %{header: header} do
      assert Encodable.encode(header) ==
               Header.unsigned_serialize(header) <> Codec.Encoder.encode(header.block_seal)
    end
  end

  describe "validate/2" do
    setup do
      {:ok, header: %Header{timeslot: 100}, state: %State{timeslot: 99}}
    end

    test "returns :ok when all conditions are met", %{header: header, state: state} do
      assert Header.validate(header, state) == :ok
    end

    test "returns error when header timeslot is not greater than state timeslot", %{state: state} do
      header = %Header{timeslot: 99}
      assert {:error, _reason} = Header.validate(header, state)
    end

    test "returns error when block time is in the future" do
      future_timeslot = Util.Time.current_time() + 10 / Util.Time.block_duration()
      header = %Header{timeslot: future_timeslot}
      state = %State{timeslot: future_timeslot - 1}

      assert {:error, message} = Header.validate(header, state)
      assert String.starts_with?(message, "Invalid block time: block_time")
    end
  end

  # Formula (282) v0.3.4
  describe "unsigned_serialize/1" do
    test "unsigned_serialize header", %{header: h} do
      # Formula (282) as is v0.3.4
      assert Header.unsigned_serialize(h) ==
               Codec.Encoder.encode({h.parent_hash, h.prior_state_root, h.extrinsic_hash}) <>
                 Codec.Encoder.encode_le(h.timeslot, 4) <>
                 Codec.Encoder.encode(
                   {NilDiscriminator.new(h.epoch), NilDiscriminator.new(h.winning_tickets_marker),
                    VariableSize.new(h.judgements_marker), VariableSize.new(h.offenders_marker),
                    Codec.Encoder.encode_le(h.block_author_key_index, 2), h.vrf_signature}
                 )
    end
  end
end
