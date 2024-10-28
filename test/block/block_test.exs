defmodule BlockTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block
  alias Block.Extrinsic.Disputes
  alias System.State
  alias Util.{Hash, Merklization}
  import Mox
  import TestHelper
  setup :verify_on_exit!

  setup_validators(1)

  setup do
    state = %State{
      timeslot: 99,
      curr_validators: build_list(3, :validator),
      prev_validators: build_list(3, :validator),
      judgements: build(:judgements),
      services: %{1 => build(:service_account)}
    }

    state_root = Merklization.merkelize_state(State.serialize(state))
    extrinsic = build(:extrinsic)
    extrinsic_hash = Util.Hash.default(Encodable.encode(extrinsic))

    valid_block = %Block{
      header: build(:header,
        timeslot: 100,
        prior_state_root: state_root,
        extrinsic_hash: extrinsic_hash
      ),
      extrinsic: extrinsic
    }

    Application.put_env(:jamixir, :original_modules, [
      Block,
      Block.Header,
      Block.Extrinsic,
      System.Validators.Safrole,
      Disputes
    ])

    on_exit(fn ->
      Application.delete_env(:jamixir, :original_modules)
    end)

    {:ok, state: state, valid_block: valid_block, state_root: state_root}
  end

  describe "encode/1" do
    test "encode block smoke test" do
      Codec.Encoder.encode(build(:block))
    end

    test "decode block smoke test" do
      extrinsic = build(:extrinsic, tickets: [build(:ticket_proof)], disputes: build(:disputes))

      header = build(:decodable_header)

      block = build(:block, header: header, extrinsic: extrinsic)

      encoded = Codec.Encoder.encode(block)
      {decoded, _} = Block.decode(encoded)
      assert decoded.header == block.header
      assert decoded.extrinsic == block.extrinsic
    end
  end

  describe "validate/2" do
    test "returns :ok for a valid block", %{state: state, valid_block: valid_block} do
      assert :ok = Block.validate(valid_block, state)
    end

    test "error when invalid state root", %{state: state, valid_block: valid_block} do
      invalid_block = put_in(valid_block.header.prior_state_root, Hash.zero())
      assert {:error, "Invalid state root"} = Block.validate(invalid_block, state)
    end

    test "returns error when header validation fails", %{state: state} do
      invalid_block = %Block{header: build(:header, timeslot: 99), extrinsic: build(:extrinsic)}
      assert {:error, _} = Block.validate(invalid_block, state)
    end

    test "returns error when guarantee validation fails", %{state: state} do
      # Invalid credential length
      invalid_extrinsic =
        build(:extrinsic, guarantees: [build(:guarantee, credentials: [{1, <<1::512>>}])])

      invalid_block = %Block{header: build(:header, timeslot: 100), extrinsic: invalid_extrinsic}
      assert {:error, _} = Block.validate(invalid_block, state)
    end

    test "returns error when disputes validation fails", %{state: state} do
      # Invalid epoch_index
      invalid_extrinsic =
        build(:extrinsic, disputes: %Disputes{verdicts: [build(:verdict, epoch_index: 100)]})

      invalid_block = %Block{header: build(:header, timeslot: 100), extrinsic: invalid_extrinsic}
      assert {:error, _} = Block.validate(invalid_block, state)
    end

    test "returns error when extrinsic hash is invalid", %{state: state, state_root: state_root} do
      extrinsic = build(:extrinsic)

      header =
        build(:header, extrinsic_hash: Hash.one(), timeslot: 100, prior_state_root: state_root)

      block = %Block{header: header, extrinsic: extrinsic}
      assert {:error, "Invalid extrinsic hash"} = Block.validate(block, state)
    end

    test "validates successfully with correct extrinsic hash", %{
      state: state,
      state_root: state_root
    } do
      extrinsic = build(:extrinsic)
      extrinsic_hash = Util.Hash.default(Encodable.encode(extrinsic))

      header =
        build(:header,
          extrinsic_hash: extrinsic_hash,
          timeslot: 100,
          prior_state_root: state_root
        )

      block = %Block{header: header, extrinsic: extrinsic}

      assert :ok = Block.validate(block, state)
    end
  end

  describe "preimage validation" do
    setup do
      Application.put_env(:jamixir, :original_modules, [
        Block.Extrinsic.Preimage
      ])

      on_exit(fn ->
        Application.delete_env(:jamixir, :original_modules)
      end)
    end

    test "returns error when preimage validation fails", %{state: state} do
      # Create two preimages with non-ascending service indices

      invalid_extrinsic =
        build(:extrinsic,
          preimages: [build(:preimage, service: 2), build(:preimage, service: 1)]
        )

      invalid_block = %Block{header: build(:header, timeslot: 100), extrinsic: invalid_extrinsic}

      assert {:error, reason} = Block.validate(invalid_block, state)
      assert reason == :not_in_order
    end
  end
end
