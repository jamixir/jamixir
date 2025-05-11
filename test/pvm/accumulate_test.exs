defmodule PVM.AccumulateTest do
  use ExUnit.Case
  alias System.State.{Accumulation, ServiceAccount}
  alias PVM.{Accumulate, Accumulate.Operand}
  alias Util.Hash
  use PVM.Instructions
  use Codec.Encoder
  import PVM.Constants.HostCallId

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
      header_timeslot = 1
      init_fn = Accumulate.Utils.initializer(n0_, header_timeslot)

      {:ok, accumulation: accumulation, service_account: service_account, init_fn: init_fn}
    end

    test "handles service without code", %{accumulation: accumulation, init_fn: init_fn} do
      assert(
        {^accumulation, [], nil, 0, []} =
          PVM.accumulate(accumulation, 1, 256, 1000, [], init_fn)
      )
    end

    test "handles nil service at service_index", %{init_fn: init_fn} do
      accumulation = %Accumulation{
        # Empty services map
        services: %{}
      }

      assert {^accumulation, [], nil, 0, []} =
               Accumulate.execute(accumulation, 0, 256, 1000, [], init_fn)
    end

    test "executes program with gas host call", %{accumulation: accumulation, init_fn: init_fn} do
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
        preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      accumulation = %{accumulation | services: %{256 => service_with_code}}

      operands = [%Operand{data: {:error, :big}}]

      {result_acc, transfers, result_hash, gas} =
        PVM.accumulate(accumulation, 0, 256, 1000, operands, init_fn)

      assert result_acc.services[256].balance == 100
      assert transfers == []
      # Gas call doesn't produce 32-byte output
      assert is_nil(result_hash)
      # Some gas was consumed
      assert gas < 1000
    end

    # TODO  - create a meaningful test
    @tag :skip
    test "executes program with multiple host calls", %{init_fn: init_fn} do
      # Program that exercises multiple host calls
      min_address = <<0x10000::64-little>>

      program =
        <<0::40>> <>
          <<
            op(:load_imm_64),
            8
          >> <>
          min_address <>
          <<
            op(:ecalli),
            host(:lookup),
            op(:fallthrough),
            op(:ecalli),
            host(:read),
            op(:fallthrough),
            op(:ecalli),
            host(:write),
            op(:fallthrough),
            op(:ecalli),
            host(:info),
            op(:fallthrough)
          >>

      bitmask =
        <<0::40>> <>
          <<1, 0>> <>
          <<0::64>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>>

      binary = PVM.Helper.init(program, bitmask)
      hash = Hash.default(binary)

      service_account = %ServiceAccount{
        balance: 100,
        code_hash: hash,
        preimage_storage_p: %{hash => binary},
        preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      accumulation = %Accumulation{
        services: %{256 => service_account}
      }

      operands = [%Operand{data: {:ok, <<>>}}]

      {result_acc, transfers, result_hash, gas} =
        Accumulate.execute(accumulation, 0, 256, 1000, operands, init_fn)

      # Basic assertions
      assert result_acc.services[256].balance == 100
      assert result_acc.services[256].code_hash == hash
      assert transfers == []
      # No 32-byte output produced
      assert is_nil(result_hash)
      # Some gas was consumed
      assert gas < 1000

      # Verify preimage storage remains intact
      assert result_acc.services[256].preimage_storage_p[hash] == binary
      assert result_acc.services[256].preimage_storage_l[{hash, byte_size(binary)}] == [0]
    end

    # TODO  - create a meaningful test
    @tag :skip
    test "executes program with accumulate-specific host calls", %{init_fn: init_fn} do
      # Program that exercises accumulate-specific host calls
      program =
        <<0::40>> <>
          <<
            # bless
            op(:ecalli),
            5,
            op(:fallthrough),
            # assign
            op(:ecalli),
            6,
            op(:fallthrough),
            # designate
            op(:ecalli),
            7,
            op(:fallthrough),
            # checkpoint
            op(:ecalli),
            8,
            op(:fallthrough),
            # new
            op(:ecalli),
            9,
            op(:fallthrough),
            # upgrade
            op(:ecalli),
            10,
            op(:fallthrough),
            # transfer
            op(:ecalli),
            11,
            op(:fallthrough),
            # quit
            op(:ecalli),
            12,
            op(:fallthrough),
            # solicit
            op(:ecalli),
            13,
            op(:fallthrough),
            # forget
            op(:ecalli),
            14,
            op(:fallthrough),
            # other
            op(:ecalli),
            278,
            op(:fallthrough)
          >>

      bitmask =
        <<0::40>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>> <>
          <<1, 0, 1>>

      binary = PVM.Helper.init(program, bitmask)
      hash = Hash.default(binary)

      service_account = %ServiceAccount{
        balance: 100,
        code_hash: hash,
        preimage_storage_p: %{hash => binary},
        preimage_storage_l: %{{hash, byte_size(binary)} => [0]}
      }

      accumulation = %Accumulation{
        services: %{256 => service_account}
      }

      {result_acc, transfers, result_hash, gas} =
        Accumulate.execute(accumulation, 0, 256, 1000, [], init_fn)

      # Basic assertions
      assert result_acc.services[256].balance == 100
      assert result_acc.services[256].code_hash == hash
      assert transfers == []
      # No 32-byte output produced
      assert is_nil(result_hash)
      # Some gas was consumed
      assert gas < 1000

      # Verify preimage storage remains intact
      assert result_acc.services[256].preimage_storage_p[hash] == binary
      assert result_acc.services[256].preimage_storage_l[{hash, byte_size(binary)}] == [0]
    end
  end
end
