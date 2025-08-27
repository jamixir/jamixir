defmodule PVM.AccumulateTest do
  use ExUnit.Case
  alias System.AccumulationResult
  alias System.State.{Accumulation, ServiceAccount}
  alias PVM.{Accumulate, Accumulate.Operand}
  alias Util.Hash
  use PVM.Instructions

  describe "accumulate /6" do
    setup do
      service_account = %ServiceAccount{
        balance: 100,
        code_hash: nil
      }

      accumulation = %Accumulation{
        services: %{
          256 => service_account
        }
      }

      n0_ = Hash.one()
      t_ = 1

      {:ok, accumulation: accumulation, service_account: service_account, n0_: n0_, timeslot_: t_}
    end

    test "handles service without code", %{accumulation: accumulation, n0_: n0_, timeslot_: t_} do
      assert AccumulationResult.new({accumulation, [], nil, 0, MapSet.new()}) ==
               PVM.accumulate(accumulation, t_, 256, 1000, [], %{n0_: n0_})
    end

    test "handles nil service at service_index", %{n0_: n0_} do
      accumulation = %Accumulation{
        # Empty services map
        services: %{}
      }

      t_ = 0

      assert AccumulationResult.new({accumulation, [], nil, 0, MapSet.new()}) ==
               Accumulate.execute(accumulation, t_, 256, 1000, [], %{n0_: n0_})
    end

    test "executes program with gas host call", %{accumulation: accumulation, n0_: n0_} do
      # Program that calls gas host function
      program =
        <<0, 0, 0, 0, 0>> <>
          <<op(:ecalli), 0, op(:fallthrough)>>

      bitmask = <<5>>
      binary = PVM.Helper.init(program, bitmask)
      hash = Hash.default(binary)

      service_with_code = %ServiceAccount{
        balance: 100,
        code_hash: hash,
        preimage_storage_p: %{hash => <<0>> <> binary},
        storage: HashedKeysMap.new(%{{hash, byte_size(binary)} => [0]})
      }

      accumulation = %{accumulation | services: %{256 => service_with_code}}

      operands = [%Operand{data: {:error, :big}}]
      t_ = 0

      acc_result = PVM.accumulate(accumulation, t_, 256, 1000, operands, %{n0_: n0_})

      assert acc_result.state.services[256].balance == 100
      assert acc_result.transfers == []
      # Gas call doesn't produce 32-byte output
      assert is_nil(acc_result.output)
      # Some gas was consumed
      assert acc_result.gas_used < 1000
    end
  end
end
