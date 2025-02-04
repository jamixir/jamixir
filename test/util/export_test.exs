defmodule Util.ExportTest do
  use ExUnit.Case
  alias Util.Export
  alias Util.Hex
  import Codec.State
  import Codec.State.Trie

  describe "get_key_name/1" do
    test "matches c1-c15 keys" do
      assert Export.get_key_name(Hex.decode16!("0x01")) == "c1"
      assert Export.get_key_name(Hex.decode16!("0x0a")) == "c10"
      assert Export.get_key_name(Hex.decode16!("0x0f")) == "c15"
    end

    test "matches account storage" do
      assert Export.get_key_name(Hex.decode16!("0x01ff00ff00ff00ff")) == "account_storage"
    end

    test "matches account preimage p" do
      assert Export.get_key_name(Hex.decode16!("0x01fe00ff00ff00ff")) == "account_preimage_p"
    end

    test "matches account preimage l" do
      assert Export.get_key_name(Hex.decode16!("0x01fd00ff00ff00ff")) == "account_preimage_l"
    end

    test "returns unknown for unmatched patterns" do
      assert Export.get_key_name(Hex.decode16!("0x00")) == "unknown"
      assert Export.get_key_name("invalid") == "unknown"
      assert Export.get_key_name(nil) == "unknown"
    end
  end

  test "export" do
    output_dir = "test/output"
    {:ok, state} = from_genesis()

    %{state_snapshot: state_snapshot_path, state_trie: state_trie_path} =
      Export.export(state, output_dir, %{epoch: 0, epoch_phase: 453})

    {:ok, loaded_state} = from_file(state_snapshot_path)
    assert state == loaded_state

    original_state_root = state_root(state)

    file_state_root =
      File.read!(state_trie_path) |> Jason.decode!() |> Map.get("state_root") |> Hex.decode16!()

    loaded_state_root = state_root(loaded_state)

    assert loaded_state_root == file_state_root
    assert loaded_state_root == original_state_root
  end
end
