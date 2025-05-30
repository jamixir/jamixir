defmodule PVM.Accumulate.UtilsTest do
  use ExUnit.Case
  alias PVM.Accumulate.Utils
  alias System.State.{Accumulation, ServiceAccount}
  alias System.DeferredTransfer
  alias PVM.Host.Accumulate.Context
  alias Util.Hash

  describe "initializer/2" do
    setup do
      n0_ = Hash.default("test_hash")
      header_timeslot = 1000

      service_state = %ServiceAccount{
        balance: 100,
        code_hash: Hash.one()
      }

      accumulation = %Accumulation{
        services: %{
          256 => service_state,
          257 => service_state
        }
      }

      {:ok,
       n0_: n0_,
       header_timeslot: header_timeslot,
       accumulation: accumulation,
       service_state: service_state}
    end



    test "initializes context correctly", %{
      n0_: n0_,
      header_timeslot: header_timeslot,
      accumulation: accumulation
    } do
      service_index = 256

      context = Utils.initializer(n0_, header_timeslot, accumulation, service_index)

      assert %{
               service: ^service_index,
               accumulation: ^accumulation,
               transfers: [],
               accumulation_trie_result: nil
             } = context

      assert is_integer(context.computed_service)
    end
  end

  describe "check/2" do
    setup do
      service_state = %ServiceAccount{
        balance: 100,
        code_hash: Hash.one()
      }

      accumulation = %Accumulation{
        services: %{
          # 0x100
          256 => service_state,
          # 0x101
          257 => service_state
        }
      }

      {:ok, accumulation: accumulation}
    end

    test "returns same index if not in services", %{accumulation: accumulation} do
      # Not in services
      i = 300
      assert Utils.check(i, accumulation) == i
    end

    test "finds next available index if in services", %{accumulation: accumulation} do
      # In services
      i = 256
      result = Utils.check(i, accumulation)
      assert result != i
      refute result in Map.keys(accumulation.services)
    end
  end

  describe "bump/1" do
    test "calculates correct bump value for various inputs" do
      # Test cases based on Formula (B.20)
      assert Utils.bump(256) == 42 + 256
      assert Utils.bump(1000) == 256 + rem(1000 - 256 + 42, 0xFFFFFE00)
    end
  end

  describe "collapse/1" do
    setup do
      service_x = %ServiceAccount{
        balance: 100,
        code_hash: Hash.one()
      }

      service_y = %ServiceAccount{
        balance: 200,
        code_hash: Hash.two()
      }

      x = %Context{
        # Contains service that's not in its accumulation
        services: %{300 => service_y},
        service: 256,
        accumulation: %Accumulation{
          services: %{
            # Service X state
            256 => service_x,
            257 => service_y
          }
        },
        computed_service: 257,
        transfers: [%DeferredTransfer{amount: 100, gas_limit: 1000}]
      }

      y = %Context{
        # Contains service from x's accumulation
        services: %{256 => service_x},
        service: 257,
        accumulation: %Accumulation{
          services: %{
            # Service Y state
            257 => service_y,
            300 => service_x
          }
        },
        computed_service: 258,
        transfers: []
      }

      {:ok, ctx: {x, y}}
    end

    test "handles valid 32-byte output", %{ctx: ctx} do
      gas = 1000
      result = Utils.collapse({gas, Hash.two(), ctx})
      x = elem(ctx, 0)

      assert {accumulation, transfers, hash, remaining_gas} = result
      # Should use x's accumulation
      assert accumulation == x.accumulation
      # service_x balance
      assert accumulation.services[256].balance == 100
      assert transfers == x.transfers
      assert hash == Hash.two()
      assert remaining_gas == gas
    end

    test "handles non-32-byte output", %{ctx: ctx} do
      output = Hash.one() <> Hash.two()
      gas = 1000
      result = Utils.collapse({gas, output, ctx})
      x = elem(ctx, 0)
      assert {accumulation, transfers, hash, remaining_gas} = result
      assert accumulation == x.accumulation
      # service_x balance
      assert accumulation.services[256].balance == 100
      assert transfers == x.transfers
      assert hash == nil
      assert remaining_gas == gas
    end

    test "handles panic output", %{ctx: ctx} do
      gas = 1000
      result = Utils.collapse({gas, :panic, ctx})
      y = elem(ctx, 1)

      assert {accumulation, transfers, hash, remaining_gas} = result
      assert accumulation == y.accumulation
      assert transfers == y.transfers
      assert hash == nil
      assert remaining_gas == gas
    end
  end

  describe "replace_service/2" do
    test "replaces service in accumulation context" do
      service_account = %ServiceAccount{
        balance: 100,
        code_hash: Hash.one()
      }

      x = %Context{
        services: %{},
        service: 256,
        accumulation: %Accumulation{services: %{256 => service_account}},
        computed_service: 257,
        transfers: []
      }

      y = %Context{
        services: %{},
        service: 257,
        accumulation: %Accumulation{services: %{}},
        computed_service: 258,
        transfers: []
      }

      ctx = {x, y}

      general_result = %PVM.Host.General.Result{
        exit_reason: :continue,
        gas: 1000,
        registers: %PVM.Registers{},
        memory: %PVM.Memory{},
        context: %ServiceAccount{
          balance: 200,
          code_hash: Hash.one()
        }
      }

      result = Utils.replace_service(general_result, ctx)

      assert %PVM.Host.Accumulate.Result{} = result
      {x_, y_} = result.context
      assert y_ == y
      assert PVM.Host.Accumulate.Context.accumulating_service(x_) == general_result.context
    end
  end
end
