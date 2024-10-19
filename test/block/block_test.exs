defmodule BlockTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block
  alias Block.Extrinsic.Disputes
  alias System.State
  alias Util.{Hash, Merklization}
  import Mox
  setup :verify_on_exit!

  defmodule ConstantsMock do
    def validator_count, do: 1
  end

  setup_all do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)
  end

  setup do
    state = %State{
      timeslot: 99,
      curr_validators: build_list(3, :validator),
      prev_validators: build_list(3, :validator),
      judgements: build(:judgements),
      services: %{1 => build(:service_account)}
    }

    state_root = Merklization.merkelize_state(State.serialize(state))

    valid_block = %Block{
      header: build(:header, timeslot: 100, prior_state_root: state_root),
      extrinsic: build(:extrinsic)
    }

    Application.put_env(:jamixir, :original_modules, [
      Block.Header,
      Block.Extrinsic,
      System.Validators.Safrole,
      Disputes
    ])

    on_exit(fn ->
      Application.delete_env(:jamixir, :original_modules)
    end)

    {:ok, state: state, valid_block: valid_block}
  end

  describe "encode/1" do
    test "encode block smoke test" do
      Codec.Encoder.encode(build(:block))
    end

    test "decode block smoke test" do
      extrinsic = build(:extrinsic, tickets: [build(:ticket_proof)], disputes: build(:disputes))

      header =
        build(:header,
          prior_state_root: Hash.random(),
          epoch_mark: {Hash.random(), [Hash.random(64)]},
          vrf_signature: Hash.random()
        )

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
