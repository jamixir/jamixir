defmodule System.State.ServicesTest do
  use ExUnit.Case
  alias System.State.{ServiceAccount, Services}
  alias Block.Extrinsic.{Assurance, Preimage}
  alias Util.Hash
  use Codec.Encoder

  import TestHelper

  setup_constants do
    def validator_count, do: 3
    def core_count, do: 3
    def gas_accumulation, do: 1000
  end

  setup_all do
    # only core index 0 will be considered available (reported availble by more then 2/3 validator set)
    assurances = [
      # Assuring for all three cores
      %Assurance{bitfield: <<0b111::3>>, validator_index: 0},
      # Assuring for first two cores
      %Assurance{bitfield: <<0b110::3>>, validator_index: 1},
      # Assuring for first and third cores
      %Assurance{bitfield: <<0b101::3>>, validator_index: 2}
    ]

    {:ok, assurances: assurances}
  end

  describe "transition/3" do
    test "preserves all services when preimages are already provided" do
      # Create a preimage and its hash
      blob = <<1, 2, 3>>
      preimage_hash = Hash.default(blob)

      # Setup services where the preimage is already stored
      init_services = %{
        1 => %ServiceAccount{
          preimage_storage_p: %{preimage_hash => "existing_data"},
          preimage_storage_l: %{{preimage_hash, 3} => [50]}
        }
      }

      preimages = [%Preimage{service: 1, blob: blob}]

      updated = Services.transition(init_services, preimages, 100)

      # Verify nothing changed
      assert updated == init_services
    end

    test "updates only services with new preimages while preserving other data" do
      blob = <<1, 2, 3>>
      blob2 = <<4, 5, 6>>
      preimage_hash = Hash.default(blob)
      preimage_hash2 = Hash.default(blob2)

      # Setup services where preimage is NOT stored
      init_services = %{
        1 => %ServiceAccount{
          # Empty storage - preimage not provided
          preimage_storage_p: %{},
          preimage_storage_l: %{{preimage_hash, 3} => []}
        },
        2 => %ServiceAccount{
          preimage_storage_p: %{preimage_hash2 => "keep_this"},
          preimage_storage_l: %{{preimage_hash2, 3} => [75]}
        }
      }

      preimages = [%Preimage{service: 1, blob: blob}, %Preimage{service: 2, blob: blob2}]

      updated = Services.transition(init_services, preimages, 100)

      # Verify service 1 was updated with new preimage
      assert Map.has_key?(updated[1].preimage_storage_p, preimage_hash)

      # Verify service 2 remained completely unchanged
      assert updated[2] == init_services[2]
    end
  end
end
