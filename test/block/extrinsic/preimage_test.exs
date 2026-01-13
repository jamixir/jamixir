defmodule Block.Extrinsic.PreimageTest do
  use ExUnit.Case
  import Codec.Encoder
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
              {Hash.default(preimage.blob), byte_size(preimage.blob)} => [4]
            })
        )

      services = %{1 => service_account}
      assert {:error, _} = Preimage.validate([preimage], services)
    end

    test "fails when service does not exist" do
      preimages = [build(:preimage, service: 1)]
      services = %{}
      assert {:error, _} = Preimage.validate(preimages, services)
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

  describe "preimages_for_new_block/2" do
    setup do
      [p20, p10] = [
        build(:preimage, service: 20, blob: <<1, 2, 3, 4>>),
        build(:preimage, service: 10, blob: <<5, 6, 7, 8>>)
      ]

      service20 =
        build(:service_account,
          storage: HashedKeysMap.new(%{{h(p20.blob), byte_size(p20.blob)} => []})
        )

      service10 =
        build(:service_account,
          storage: HashedKeysMap.new(%{{h(p10.blob), byte_size(p10.blob)} => []})
        )

      services = %{10 => service10, 20 => service20, 3 => build(:service_account)}

      {:ok, preimages: [p10, p20], services: services}
    end

    test "selects preimages for new block", %{preimages: [p10, p20], services: services} do
      preimage_candidates = [p20, p10, build(:preimage, service: 3, blob: <<7, 8, 9>>)]

      [^p10, ^p20] = Preimage.preimages_for_new_block(preimage_candidates, services)
    end

    test "preimages are sorted by service and blob", %{preimages: [p10 | _], services: services} do
      p10b = %Preimage{service: 10, blob: <<0, 1, 2>>}
      preimage_candidates = [p10, p10b]
      # set other preimage to be in requested state
      services = put_in(services, [10, :storage, {h(p10b.blob), byte_size(p10b.blob)}], [])
      [^p10b, ^p10] = Preimage.preimages_for_new_block(preimage_candidates, services)
    end
  end
end
