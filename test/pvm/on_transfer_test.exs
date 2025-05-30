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

      extra_args = %{n0_: Hash.one()}

      {:ok, basic_service: basic_service, transfer: transfer, extra_args: extra_args}
    end

    test "returns service directly when code is not found", %{
      basic_service: service,
      transfer: transfer,
      extra_args: extra_args
    } do
      services = %{1 => service}

      {result, _g} = PVM.on_transfer(services, 0, 1, [transfer], extra_args)

      expected_balance = service.balance + transfer.amount

      # First assert everything except balance matches
      assert Map.drop(result, [:balance]) == Map.drop(service, [:balance])
      # Then assert balance separately
      assert result.balance == expected_balance
    end

    test "returns service directly when transfer is empty", %{
      basic_service: service,
      extra_args: extra_args
    } do
      services = %{1 => service}

      {result, _} = PVM.on_transfer(services, 0, 1, [], extra_args)

      assert result == service
    end
  end
end
