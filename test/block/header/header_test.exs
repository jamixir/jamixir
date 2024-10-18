defmodule Block.HeaderTest do
  use ExUnit.Case
  import TestHelper
  import Jamixir.Factory

  alias Block.Header
  alias Codec.{NilDiscriminator, VariableSize}
  alias System.State
  alias Util.{Hash, Merklization}

  defmodule ConstantsMock do
    def validator_count, do: 1
  end

  setup do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)
  end

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

  describe "valid_extrinsic_hash?/2" do
    test "valid_extrinsic_hash?/2 wrong hash" do
      extrinsic = build(:extrinsic)
      header = %Header{extrinsic_hash: "other"}
      assert !Header.valid_extrinsic_hash?(header, extrinsic)
    end

    test "valid_extrinsic_hash?/2 correct" do
      extrinsic = build(:extrinsic)
      header = %Header{extrinsic_hash: Util.Hash.default(Codec.Encoder.encode(extrinsic))}
      assert Header.valid_extrinsic_hash?(header, extrinsic)
    end
  end

  setup do
    {:ok, header: %Header{block_seal: <<123::256>>}}
  end

  # Formula (302) v0.4.1
  describe "encode/1" do
    test "encode header smoke test" do
      assert Encodable.encode(build(:header))
    end

    test "encode header", %{header: header} do
      assert Encodable.encode(header) ==
               Header.unsigned_encode(header) <> Codec.Encoder.encode(header.block_seal)
    end
  end

  describe "decode/1" do
    test "unsigned decode header smoke test" do
      header = build(:header)
      encoded = Header.unsigned_encode(header)
      {decoded, _} = Header.unsigned_decode(encoded)
      assert decoded == header
    end

    test "unsigned decode header will all fields" do
      header =
        build(:header,
          prior_state_root: Hash.random(),
          epoch_mark: {Hash.random(), [Hash.random(64)]}
        )

      encoded = Header.unsigned_encode(header)
      {decoded, _} = Header.unsigned_decode(encoded)
      assert decoded == header
    end
  end

  describe "validate/2" do
    setup do
      state = %State{timeslot: 99}
      state_root = Merklization.merkelize_state(State.serialize(state))

      {:ok, header: %Header{timeslot: 100, prior_state_root: state_root}, state: state}
    end

    test "returns :ok when all conditions are met", %{header: header, state: state} do
      assert Header.validate(header, state) == :ok
    end

    test "returns error when header timeslot is not greater than state timeslot", %{state: state} do
      header = %Header{timeslot: 99}
      assert {:error, _reason} = Header.validate(header, state)
    end

    test "returns error when block time is in the future" do
      future_timeslot = Util.Time.current_time() + 10 / Constants.slot_period()
      header = %Header{timeslot: future_timeslot}
      state = %State{timeslot: future_timeslot - 1}

      assert {:error, message} = Header.validate(header, state)
      assert String.starts_with?(message, "Invalid block time: block_time")
    end

    test "returns error when state root is invalid", %{state: state} do
      header = %Header{timeslot: 100, prior_state_root: "invalid"}
      assert {:error, "Invalid state root"} = Header.validate(header, state)
    end
  end

  # Formula (303) v0.4.1
  describe "unsigned_encode/1" do
    test "unsigned_encode header", %{header: h} do
      assert Header.unsigned_encode(h) ==
               Codec.Encoder.encode({h.parent_hash, h.prior_state_root, h.extrinsic_hash}) <>
                 Codec.Encoder.encode_le(h.timeslot, 4) <>
                 Codec.Encoder.encode(
                   {NilDiscriminator.new(h.epoch_mark),
                    NilDiscriminator.new(h.winning_tickets_marker),
                    VariableSize.new(h.offenders_marker),
                    Codec.Encoder.encode_le(h.block_author_key_index, 2), h.vrf_signature}
                 )
    end
  end
end
