defmodule System.State.ServicesTest do
  use ExUnit.Case
  alias System.State.{ServiceAccount, Services}
  alias Block.Extrinsic.{Assurance, Preimage}

  defmodule ConstantsMock do
    def validator_count, do: 3
    def core_count, do: 3
    def gas_accumulation, do: 1000
  end

  setup_all do
    Application.put_env(:jamixir, Constants, ConstantsMock)

    on_exit(fn ->
      Application.delete_env(:jamixir, Constants)
    end)

    # only core index 0 will be considered available (reported availble by more then 2/3 validator set)
    assurances = [
      # Assuring for all three cores
      %Assurance{assurance_values: <<0b111::3>>, validator_index: 0},
      # Assuring for first two cores
      %Assurance{assurance_values: <<0b110::3>>, validator_index: 1},
      # Assuring for first and third cores
      %Assurance{assurance_values: <<0b101::3>>, validator_index: 2}
    ]

    {:ok, assurances: assurances}
  end

  describe "process_preimages/3" do
    test "processes preimages correctly" do
      init_services = %{1 => %ServiceAccount{}, 2 => %ServiceAccount{}}

      preimages = [
        %Preimage{service: 1, blob: <<1, 2, 3>>},
        %Preimage{service: 3, blob: <<4, 5, 6>>}
      ]

      ts = 100

      updated = Services.process_preimages(init_services, preimages, ts)

      assert map_size(updated) == 3
      # Service index 2 is not affected
      assert updated[2] == init_services[2]

      # Service index 1 and 3 are updated
      for {idx, data} <- [{1, <<1, 2, 3>>}, {3, <<4, 5, 6>>}] do
        hash = Util.Hash.default(data)
        assert updated[idx].preimage_storage_p[hash] == data
        assert updated[idx].preimage_storage_l[{hash, 3}] == [ts]
      end
    end
  end
end
