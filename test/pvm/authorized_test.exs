defmodule PVM.AuthorizedTest do
  use ExUnit.Case
  alias Block.Extrinsic.WorkPackage
  alias System.State.ServiceAccount
  alias Util.Hash
  use PVM.Instructions
  use Codec.{Encoder, Decoder}

  describe "authorized/3" do
    setup do
      # Create a service account that will store our test programs
      service_account = %ServiceAccount{
        preimage_storage_p: %{},
        preimage_storage_l: %{}
      }

      {:ok, service_account: service_account}
    end

    test "returns binary data when program calls gas host function", %{
      service_account: service_account
    } do
      # Program that:
      # 1. sets up the message in memory (page 16)
      # 2. sets up registers 10,11 to be the start and end address of the message
      # 3. calls the gas host function
      # 4. halts and returns the message
      message = "Hello Jamixir PVM"
      page_size = %PVM.Memory{}.page_size
      start_addr = page_size * 16
      end_addr = page_size * 16 + byte_size(message)

      # r11 = 100 + message length
      program =
        <<
          # Set up return registers using load_imm_64
          # r10 = 100 (start address)
          op(:load_imm_64),
          10
        >> <>
          e_le(start_addr, 8) <>
          <<op(:load_imm_64), 11>> <>
          e_le(end_addr, 8) <>
          <<
            # Call gas host function
            # gas host call
            op(:ecalli),
            0,
            op(:fallthrough)
          >>

      bitmask = <<1>> <> e_le(0, 9) <> <<1>> <> e_le(0, 9) <> <<1, 0, 1>>

      binary = PVM.Helper.init(program, bitmask, message)
      hash = Hash.default(binary)

      # Store program in service account
      service_account = %{
        service_account
        | preimage_storage_p: %{hash => binary},
          preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      work_package = %WorkPackage{
        service: 1,
        authorization_code_hash: hash
      }

      result = PVM.authorized(work_package, 0, %{1 => service_account})
      assert result == message
    end

    test "not gas host function and also panics", %{
      service_account: service_account
    } do
      # Program that calls a non-gas host function (e.g., 1)
      program = <<
        # non-gas host call
        op(:ecalli),
        2,
        op(:fallthrough)
      >>

      bitmask = <<1, 0, 1>>
      binary = PVM.Helper.init(program, bitmask, nil, false)
      hash = Hash.default(binary)

      # Store program in service account
      service_account = %{
        service_account
        | preimage_storage_p: %{hash => binary},
          preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      work_package = %WorkPackage{
        service: 1,
        authorization_code_hash: hash
      }

      result = PVM.authorized(work_package, 0, %{1 => service_account})
      assert result == :panic
    end

    # test "returns :out_of_gas when program runs out of gas", %{service_account: service_account} do
    #   # Program that will consume all gas through repeated gas host calls
    #   program = <<
    #     # gas host call
    #     op(:ecalli),
    #     18,
    #     op(:fallthrough),
    #     # gas host call
    #     op(:ecalli),
    #     18,
    #     op(:fallthrough),
    #     # gas host call
    #     op(:ecalli),
    #     18,
    #     op(:fallthrough)
    #   >>

    #   bitmask = for <<_::1 <- program>>, into: <<>>, do: <<1::1>>
    #   binary = PVM.Helper.init(program, bitmask)
    #   hash = Hash.default(binary)

    #   # Store program in service account
    #   service_account = %{
    #     service_account
    #     | preimage_storage_p: %{hash => binary},
    #       preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
    #   }

    #   work_package = %WorkPackage{
    #     service: 1,
    #     authorization_code_hash: hash
    #   }

    #   # Use minimal gas to ensure out_of_gas
    #   result = PVM.authorized(work_package, 0, %{1 => service_account})
    #   assert result == :out_of_gas
    # end
  end
end
