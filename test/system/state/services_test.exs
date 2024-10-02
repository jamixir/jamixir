defmodule System.State.ServicesTest do
  use ExUnit.Case
  alias System.State.Services
  alias System.State.ServiceAccount
  alias Block.Extrinsic.Preimage

  describe "process_preimages/3" do
    test "processes preimages correctly" do
      init_services = %{1 => %ServiceAccount{}, 2 => %ServiceAccount{}}

      preimages = [
        %Preimage{service_index: 1, data: <<1, 2, 3>>},
        %Preimage{service_index: 3, data: <<4, 5, 6>>}
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
