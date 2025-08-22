defmodule PVM.AuthorizedTest do
  use ExUnit.Case
  alias Block.Extrinsic.WorkPackage
  alias System.State.ServiceAccount
  alias Util.Hash
  use PVM.Instructions
  import PVM.Constants.HostCallId

  describe "authorized/3" do
    setup do
      # Create a service account that will store our test programs
      service_account = %ServiceAccount{preimage_storage_p: %{}}

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
      start_addr = 0x1_0000
      mem_size = byte_size(message)

      # r11 = 100 + message length
      program =
        <<op(:load_imm_64), 8, mem_size::64-little, op(:ecalli), host(:gas), op(:fallthrough),
          op(:load_imm_64), 7, start_addr::64-little, op(:fallthrough)>>

      bitmask = <<128, 44, 1>>

      binary = <<0>> <> PVM.Helper.init(program, bitmask, message)
      hash = Hash.default(binary)

      # Store program in service account
      service_account = %{
        service_account
        | preimage_storage_p: %{hash => binary},
          storage: HashedKeysMap.new(%{{hash, byte_size(binary)} => [0]})
      }

      work_package = %WorkPackage{
        service: 1,
        authorization_code_hash: hash
      }

      {result, _gas_used} = PVM.authorized(work_package, 0, %{1 => service_account})
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
        op(:fallthrough),
        op(:fallthrough),
        op(:fallthrough),
        op(:fallthrough),
        op(:fallthrough),
        op(:fallthrough)
      >>

      bitmask = <<191>>
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

      {result, _gas_used} = PVM.authorized(work_package, 0, %{1 => service_account})
      assert result == :panic
    end
  end
end
