defmodule Jamixir.ChainSpecTest do
  use ExUnit.Case
  alias Jamixir.ChainSpec
  alias Jamixir.Genesis

  @moduletag :chainspec

  describe "chainspec conversion" do
    test "converts genesis.json to JIP-4 chainspec format" do
      # Use the default genesis file
      {:ok,
       %{
         id: _,
         genesis_header: _,
         genesis_state: _,
         protocol_parameters: _,
         bootnodes: b
       }} = ChainSpec.from_genesis()

      assert is_list(b)
    end

    test "writes chainspec to file and reads it back" do
      # Create a temporary file
      tmp_file = Path.join(System.tmp_dir!(), "test_chainspec_#{:rand.uniform(1000)}.json")

      try do
        {:ok, original_chainspec} = ChainSpec.from_genesis()
        :ok = ChainSpec.to_file(original_chainspec, tmp_file)

        {:ok, loaded_chainspec} = ChainSpec.from_file(tmp_file)

        assert loaded_chainspec == original_chainspec
      after
        File.rm(tmp_file)
      end
    end
  end

  describe "bootnode parsing" do
    test "parses valid bootnode string" do
      bootnode = "evysk4p563r2kappaebqykryquxw5lfcclvf23dqqhi5n765h4kkb@192.168.50.18:62061"
      {:ok, parsed} = ChainSpec.parse_bootnode(bootnode)

      assert parsed.name == "evysk4p563r2kappaebqykryquxw5lfcclvf23dqqhi5n765h4kkb"
      assert parsed.ip == "192.168.50.18"
      assert parsed.port == 62061
    end

    test "returns error for invalid format" do
      assert {:error, _} = ChainSpec.parse_bootnode("invalid")
      assert {:error, _} = ChainSpec.parse_bootnode("name@ip")
      assert {:error, _} = ChainSpec.parse_bootnode("name@ip:notaport")
    end
  end

  describe "chainspec detection" do
    test "detects JIP-4 chainspec file format" do
      # Create a minimal chainspec
      tmp_file = Path.join(System.tmp_dir!(), "test_chainspec_#{:rand.uniform(1000)}.json")

      chainspec = %{
        id: "test",
        bootnodes: [],
        genesis_header: "00",
        genesis_state: %{},
        protocol_parameters: "00"
      }

      try do
        {:ok, json} = Jason.encode(chainspec)
        File.write!(tmp_file, json)

        assert Genesis.chainspec_file?(tmp_file) == true
      after
        File.rm(tmp_file)
      end
    end

    test "does not detect regular genesis file as chainspec" do
      genesis_file = Genesis.default_file()

      # The default genesis.json should not be detected as a chainspec
      refute Genesis.chainspec_file?(genesis_file)
    end
  end

  describe "state serialization round-trip" do
    test "can recover state from chainspec format" do
      # Load original state from genesis
      {:ok, original_state} = Codec.State.from_genesis()

      # Convert to chainspec format
      {:ok, chainspec} = ChainSpec.from_genesis()

      # Load state back from chainspec
      {:ok, spec_state} = ChainSpec.get_state(chainspec)
      assert spec_state == original_state
    end

    test "can recover header from chainspec format" do
      {:ok, chainspec} = ChainSpec.from_genesis()
      {:ok, header} = ChainSpec.get_header(chainspec)
      assert header == Genesis.genesis_block_header()
    end
  end
end
