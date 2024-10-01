defmodule Block.Extrinsic.PreimageTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Preimage
  alias Util.Hash

  describe "validate/2 - fail cases" do
    test "fails when service indices are not unique" do
      preimages = [
        build(:preimage, service_index: 1),
        build(:preimage, service_index: 1)
      ]

      services = %{1 => build(:service_account)}
      assert {:error, _} = Preimage.validate(preimages, services)
    end

    test "fails when service indices are not in ascending order" do
      preimages = [
        build(:preimage, service_index: 2),
        build(:preimage, service_index: 1)
      ]

      services = %{1 => build(:service_account), 2 => build(:service_account)}
      assert {:error, _} = Preimage.validate(preimages, services)
    end

    test "fails when preimage hash is in service_account.preimage_storage_p" do
      preimage = build(:preimage, service_index: 1)

      service_account =
        build(:service_account, preimage_storage_p: %{Hash.default(preimage.data) => true})

      services = %{1 => service_account}
      assert {:error, _} = Preimage.validate([preimage], services)
    end

    test "fails when preimage is already in preimage_storage_l" do
      preimage = build(:preimage, service_index: 1)

      service_account =
        build(:service_account,
          preimage_storage_l: %{
            {Hash.default(preimage.data), byte_size(preimage.data)} => [:some_existing_data]
          }
        )

      services = %{1 => service_account}
      assert {:error, _} = Preimage.validate([preimage], services)
    end
  end

  describe "validate/2 - pass cases" do
    test "passes with valid preimages and services" do
      preimages = [build(:preimage, service_index: 1), build(:preimage, service_index: 2)]

      services = %{
        1 => build(:service_account),
        2 => build(:service_account)
      }

      assert :ok = Preimage.validate(preimages, services)
    end
  end
end
