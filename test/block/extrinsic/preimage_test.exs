defmodule Block.Extrinsic.PreimageTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block.Extrinsic.Preimage
  alias Util.Hash

  describe "validate/2 - fail cases" do
    test "fails when preimages are not unique" do
      preimages = [
        build(:preimage, service: 1, blob: <<1, 2, 3>>),
        build(:preimage, service: 1, blob: <<1, 2, 3>>)
      ]

      services = %{1 => build(:service_account)}

      assert {:error, _} = Preimage.validate(preimages, services)
    end

    test "fails when service indices are not in ascending order" do
      preimages = [build(:preimage, service: 2), build(:preimage, service: 1)]

      services = %{1 => build(:service_account), 2 => build(:service_account)}
      assert {:error, _} = Preimage.validate(preimages, services)
    end

    test "fails when preimage hash is in service_account.preimage_storage_p" do
      preimage = build(:preimage, service: 1)

      service_account =
        build(:service_account, preimage_storage_p: %{Hash.default(preimage.blob) => true})

      services = %{1 => service_account}
      assert {:error, _} = Preimage.validate([preimage], services)
    end

    test "fails when preimage is already in preimage_storage_l" do
      preimage = build(:preimage, service: 1)

      service_account =
        build(:service_account,
          storage:
            HashedKeysMap.new(%{
              {Hash.default(preimage.blob), byte_size(preimage.blob)} => [:some_existing_data]
            })
        )

      services = %{1 => service_account}
      assert {:error, _} = Preimage.validate([preimage], services)
    end
  end

  describe "validate/2 - pass cases" do
    test "passes with valid preimages and services" do
      preimages = [build(:preimage, service: 1), build(:preimage, service: 2)]
      keys = Enum.map(preimages, &{Hash.default(&1.blob), byte_size(&1.blob)})

      services = %{
        1 => build(:service_account, storage: HashedKeysMap.new(%{Enum.at(keys, 0) => []})),
        2 => build(:service_account, storage: HashedKeysMap.new(%{Enum.at(keys, 1) => []}))
      }

      assert :ok = Preimage.validate(preimages, services)
    end
  end

  describe "encode / decode" do
    test "encode/decode" do
      preimage = build(:preimage)
      encoded = Encodable.encode(preimage)
      {decoded, _} = Preimage.decode(encoded)
      assert preimage == decoded
    end
  end
end
