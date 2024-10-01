defmodule Block.HeaderTest do
  use ExUnit.Case
  import Jamixir.Factory

  alias Block.Header
  alias System.State
  alias Codec.{NilDiscriminator, VariableSize}
  import Mox
  setup :verify_on_exit!

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
      Application.put_env(:jamixir, :original_modules, [
        Block.Header,
        Util.Time
      ])

      on_exit(fn ->
        Application.delete_env(:jamixir, :original_modules)
      end)

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
      future_timeslot = Util.Time.current_time() + 10 / Constants.slot_period()
      header = %Header{timeslot: future_timeslot}
      state = %State{timeslot: future_timeslot - 1}

      assert {:error, message} = Header.validate(header, state)
      assert String.starts_with?(message, "Invalid block time: block_time")
    end
  end

  describe "validate/2 with actual Storage" do
    setup do

      header = %Header{timeslot: 100}
      state = %State{timeslot: 99}
      Storage.start_link()
      :mnesia.clear_table(Storage.table_name())
      {:ok, header: header, state: state}
    end

    test "returns :ok when parent hash exists in storage", %{
      header: header,
      state: state
    } do
      {:ok, parent_hash} = Storage.put(%Header{timeslot: 99})
      header = %{header | parent_hash: parent_hash}

      # Ensure the parent hash exists in storage
      assert Storage.exists?(parent_hash)

      assert :ok = Header.validate(header, state)
    end

    test "returns error when parent hash is not found in storage", %{header: header, state: state} do
      # Use a non-existent parent hash
      header = %{header | parent_hash: <<2::256>>}

      assert {:error, "Parent hash not found in storage"} = Header.validate(header, state)
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
