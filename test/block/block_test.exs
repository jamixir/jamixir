defmodule BlockTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.TicketProof
  alias Block
  alias Block.{Extrinsic, Extrinsic.Disputes}
  alias Codec.State.Trie
  alias System.State
  alias Util.{Export, Hash, Time}
  import Mox
  import OriginalModules
  import Codec.Encoder
  setup :verify_on_exit!

  setup do
    state = %State{
      timeslot: 99,
      curr_validators: build_list(3, :validator),
      prev_validators: build_list(3, :validator),
      judgements: build(:judgements),
      services: %{1 => build(:service_account)}
    }

    state_root = Trie.state_root(state)
    extrinsic = build(:extrinsic)
    extrinsic_hash = Extrinsic.calculate_hash(extrinsic)

    parent = build(:decodable_header, timeslot: 99)
    Storage.put(parent)

    valid_block = %Block{
      header:
        build(:header,
          timeslot: 100,
          prior_state_root: state_root,
          extrinsic_hash: extrinsic_hash,
          parent_hash: h(e(parent))
        ),
      extrinsic: extrinsic
    }

    Application.put_env(:jamixir, :original_modules, [
      :validate_extrinsic_hash,
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
      block = build(:decodable_block)
      {decoded, _} = Block.decode(e(block))
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
      assert {:error, message} = Block.validate(invalid_block, state)
      assert String.starts_with?(message, "Invalid state root.")
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

    test "returns error when extrinsic hash is invalid", %{
      state: state,
      valid_block: valid_block
    } do
      block = put_in(valid_block.header.extrinsic_hash, Hash.one())
      assert {:error, "Invalid extrinsic hash"} = Block.validate(block, state)
    end
  end

  describe "preimage validation" do
    setup do
      Application.put_env(:jamixir, :original_modules, [
        Util.Collections,
        Block.Extrinsic.Preimage
      ])

      on_exit(fn -> Application.delete_env(:jamixir, :original_modules) end)
    end

    test "returns error when preimage validation fails", %{state: state} do
      # Create two preimages with non-ascending service indices

      invalid_extrinsic =
        build(:extrinsic,
          preimages: [build(:preimage, service: 2), build(:preimage, service: 1)]
        )

      invalid_block = %Block{header: build(:header, timeslot: 100), extrinsic: invalid_extrinsic}

      assert {:error, reason} = Block.validate(invalid_block, state)
      assert reason == :preimages_not_sorted_unique
    end
  end

  describe "validate_refinement_context" do
    test "returns error when refinement context is invalid" do
      with_original_modules([:validate_refinement_context]) do
        header = build(:header, timeslot: 100)
        extrinsic = build(:extrinsic, guarantees: [build(:guarantee)])

        assert {:error, "Refinement context is invalid"} =
                 Block.validate_refinement_context(header, extrinsic)
      end
    end

    test "returns :ok when refinement context is valid" do
      with_original_modules([:validate_refinement_context]) do
        parent = build(:decodable_header, timeslot: 100)
        header = build(:header, timeslot: 101, parent_hash: h(e(parent)))

        rc = build(:refinement_context, timeslot: 100, lookup_anchor: h(e(parent)))
        work_report = build(:work_report, refinement_context: rc)

        extrinsic =
          build(:extrinsic, guarantees: [build(:guarantee, work_report: work_report)])

        Storage.put([parent, header])
        assert :ok = Block.validate_refinement_context(header, extrinsic)
      end
    end
  end

  setup_all do
    Storage.put(Hash.zero(), build(:header, timeslot: 0))
    :ok
  end

  describe "new/4" do
    test "creates a valid fallback block no extrinsics" do
      %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)

      end_time = Time.current_timeslot()
      initial_time = end_time - Constants.slot_period() - 1

      for t <- initial_time..end_time, reduce: {state, nil} do
        {state, header_hash} ->
          {:ok, b} = Block.new(%Extrinsic{}, header_hash, state, t, key_pairs: key_pairs)
          {:ok, h} = Storage.put(b.header)
          {:ok, state} = State.add_block(state, b)
          {state, h}
      end
    end

    test "create a valid block passing all key pairs" do
      %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)
      {:ok, _} = Block.new(%Extrinsic{}, nil, state, 100, key_pairs: key_pairs)
    end

    test "create a valid block with env key fallback mode new epoch" do
      %{state: state, key_pairs: [{priv, pub} | _]} = build(:genesis_state_with_safrole)

      # use fixed entropy pool to avoid randomness and predictable block creation turn
      state = put_in(state.entropy_pool, build(:fixed_entropy_pool))
      # Set the first key in the environment
      KeyManager.load_keys(%{bandersnatch: pub, bandersnatch_priv: priv})
      # 101 is the correct timeslot based on the fixed entropy pool
      {:ok, _} = Block.new(%Extrinsic{}, nil, state, 101)
    end

    test "create a valid block with ticket proofs same epoch" do
      %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)
      state = %{state | safrole: %{state.safrole | ticket_accumulator: []}}
      i = 1
      {priv, pub} = Enum.at(key_pairs, i)
      KeyManager.load_keys(%{bandersnatch: pub, bandersnatch_priv: priv})

      {proof, _} =
        TicketProof.create_proof(state.curr_validators, state.entropy_pool.n2, {priv, pub}, i, 2)

      ticket = %TicketProof{signature: proof, attempt: 2}

      {:ok, block} = Block.new(%Extrinsic{tickets: [ticket]}, nil, state, state.timeslot + 1)
      {:ok, _} = State.add_block(state, block)
    end

    test "can't create block ticket proofs from other validator" do
      %{state: state, key_pairs: [{priv0, pub0} | _]} = build(:genesis_state_with_safrole)

      # Set the first key in the environment
      KeyManager.load_keys(%{bandersnatch: pub0, bandersnatch_priv: priv0})

      {:error, :not_our_slot} = Block.new(%Extrinsic{}, nil, state, state.timeslot + 1)
    end

    test "cant't create block if it doesnt have the author key" do
      # test the no-keys scenario
      Application.delete_env(:jamixir, :keys)

      %{state: state} = build(:genesis_state_with_safrole)
      {:error, :no_valid_keys_found} = Block.new(%Extrinsic{}, nil, state, 100)
    end
  end

  @epoch_count 4
  describe "generate state and block dumps" do
    @describetag :generate_blocks
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("jamixir_test_#{:erlang.unique_integer()}")
      IO.puts("Writing test data to #{tmp_dir}")
      File.mkdir_p!("#{tmp_dir}/blocks")
      File.mkdir_p!("#{tmp_dir}/state_snapshots")
      File.mkdir_p!("#{tmp_dir}/state_transitions")
      Application.delete_env(:jamixir, :original_modules)
      tn = Time.current_timeslot()
      t0 = tn - Constants.slot_period() * @epoch_count
      %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)
      {:ok, t0: t0, tn: tn, state: state, key_pairs: key_pairs, tmp_dir: tmp_dir}
    end

    test "fallback", %{state: state, t0: t0, tn: tn, key_pairs: key_pairs, tmp_dir: tmp_dir} do
      Export.export(state, tmp_dir, "genesis")

      for t <- t0..tn, reduce: {state, Hash.zero()} do
        {state, header_hash} ->
          {:ok, b} = Block.new(%Extrinsic{}, header_hash, state, t, key_pairs: key_pairs)

          filename = "#{tmp_dir}/blocks/block_#{b.header.timeslot}.bin"

          bin1 = Codec.Encoder.encode(b)
          {b_check, _} = Block.decode(bin1)
          assert b == b_check
          :ok = File.write(filename, bin1)

          {:ok, h} = Storage.put(b.header)
          {:ok, state} = State.add_block(state, b)
          Export.export(state, "#{tmp_dir}/state_snapshots")
          {state, h}
      end

      IO.puts("State and blocks exported to #{tmp_dir}")
    end
  end
end
