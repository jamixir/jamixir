defmodule BlockTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block
  alias Block.Extrinsic.Disputes
  alias System.State
  import Mox
  setup :verify_on_exit!

  setup do
    state = %State{
      timeslot: 99,
      curr_validators: build_list(3, :validator),
      prev_validators: build_list(3, :validator),
      judgements: build(:judgements),
      services: %{1 => build(:service_account)}
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

    {:ok, state: state}
  end

  describe "encode/1" do
    test "encode block smoke test" do
      Codec.Encoder.encode(build(:block))
    end
  end

  describe "validate/2" do
    test "returns :ok for a valid block", %{state: state} do
      valid_block = %Block{header: build(:header, timeslot: 100), extrinsic: build(:extrinsic)}
      assert :ok = Block.validate(valid_block, state)
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
