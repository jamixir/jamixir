defmodule Block.HeaderTest do
  use ExUnit.Case
  import TestHelper

  alias Block.Header
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
    test "encode header", %{header: header} do
      assert Encodable.encode(header) ==
               Header.unsigned_serialize(header) <> Codec.Encoder.encode(header.block_seal)
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
          {NilDiscriminator.new(h.epoch),
          NilDiscriminator.new(h.winning_tickets_marker),
          VariableSize.new(h.judgements_marker),
          VariableSize.new(h.o),
          Codec.Encoder.encode_le(h.block_author_key_index,2),
          h.vrf_signature,
        }
        )

      end
  end
end
