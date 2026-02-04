defmodule PVM.AccumulateTest do
  use ExUnit.Case
  alias Jamixir.ChainSpec
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

      accumulation_inputs = [%Operand{data: {:error, :big}}]
      t_ = 0

      acc_result = PVM.accumulate(accumulation, t_, 256, 1000, accumulation_inputs, %{n0_: n0_})

      assert acc_result.state.services[256].balance == 100
      assert acc_result.transfers == []
      # Gas call doesn't produce 32-byte output
      assert is_nil(acc_result.output)
      # Some gas was consumed
      assert acc_result.gas_used < 1000
    end
  end

  describe "accumulation integration tests" do
    test "bootstrap service - vm new service" do
      state = ChainSpec.bootstrap_state()

      accumulation = %Accumulation{services: %{0 => state.services[0]}}

      inputs_hex =
        "0x01003e0e636827f55a836ce65b0fbfa73a46edc5d76bf9d94ba1223c987093c7061900000000000000000000000000000000000000000000000000000000000000002357426f2313559a271d6782dc00197b379f79cbe3c6a1e72f61f7b592c509f8e6a04b842d4eb6b03dbd60ad97037898359ccf465c8f8e31985ee18c281337a2e08096980080c301000806a2111844d41615be6eb7760647537b8e3f5a42f96921930913255ab4d1bdc32a04000000000040420f000000000040420f000000000000ca9a3b0000000000ffffffffffffff7f000000006f0a56dd38bc100f39d69f7eeb973dc17bdefb4cf92f999c6108b2979c37a2e900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

      inputs_bin = Util.Hex.decode16!(inputs_hex)

      {inputs, _} = Accumulation.decode_inputs(inputs_bin)

      PVM.accumulate(accumulation, 100, 0, 7_000_000_000, inputs, %{n0_: Hash.random()})
    end
  end

  def filter_prefix(files, prefix) do
    for f <- files,
        f |> String.starts_with?(prefix),
        timeslot = String.replace(f, "#{prefix}_", "") |> String.replace(".bin", "") do
      String.to_integer(timeslot)
    end
  end
end
