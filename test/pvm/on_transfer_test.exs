defmodule PVM.OnTransferTest do
  use ExUnit.Case
  alias System.DeferredTransfer
  alias System.State.ServiceAccount
  alias Util.Hash
  use PVM.Instructions
  use Codec.Encoder

  describe "on_transfer/4" do
    setup do
      # Basic service account with no code
      basic_service = %ServiceAccount{
        code_hash: Hash.one(),
        balance: 100
      }

      # Transfer that will be applied
      transfer = %DeferredTransfer{
        amount: 50,
        gas_limit: 1000
      }

      {:ok, basic_service: basic_service, transfer: transfer}
    end

    test "returns service directly when code is not found", %{
      basic_service: service,
      transfer: transfer
    } do
      services = %{1 => service}

      result = PVM.on_transfer(services, 0, 1, [transfer])

      expected_balance = service.balance + transfer.amount

      # First assert everything except balance matches
      assert Map.drop(result, [:balance]) == Map.drop(service, [:balance])
      # Then assert balance separately
      assert result.balance == expected_balance
    end

    test "returns service directly when transfer is empty", %{basic_service: service} do
      services = %{1 => service}

      result = PVM.on_transfer(services, 0, 1, [])

      assert result == service
    end

    #TODO  - create a meaningful test
    @tag :skip
    test "executes all host functions when code_hash exists" do
      # transfer entry point is counter: 10
      program =
        <<0::80>> <>
          <<
            # gas
            op(:ecalli),
            0,
            op(:fallthrough),
            # lookup
            op(:ecalli),
            1,
            op(:fallthrough),
            # read
            op(:ecalli),
            2,
            op(:fallthrough),
            # write
            op(:ecalli),
            3,
            op(:fallthrough),
            # info
            op(:ecalli),
            4,
            op(:fallthrough),
            # fallback case
            op(:ecalli),
            5,
            op(:fallthrough)
          >>

      bitmask =
        <<0::80>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>>

      binary = PVM.Helper.init(program, bitmask)
      hash = Hash.default(binary)

      service = %ServiceAccount{
        code_hash: hash,
        balance: 100,
        preimage_storage_p: %{hash => binary},
        preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      transfer = %DeferredTransfer{
        amount: 50,
        # Enough gas for all operations
        gas_limit: 10000
      }

      services = %{1 => service}

      result = PVM.on_transfer(services, 0, 1, [transfer])

      # Basic assertions
      assert result.balance == 150
      assert result.code_hash == hash
      # The program should have executed successfully through all host calls
    end
  end
end
