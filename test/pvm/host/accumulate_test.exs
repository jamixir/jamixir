defmodule PVM.Host.Accumulate.BlessTest do
  use ExUnit.Case
  alias System.DeferredTransfer
  alias System.State.{Accumulation, ServiceAccount, PrivilegedServices}
  alias Util.Hash
  alias PVM.Host.Accumulate
  alias PVM.{Memory, Host.Accumulate.Context, Registers, Host.Accumulate.Result, Accumulate.Utils}
  import PVM.Constants.HostCallResult
  use Codec.{Encoder, Decoder}

  setup_all do
    {:ok, context: {%Context{}, %Context{}}}
  end

  describe "bless/4" do
    setup do
      # Create a test gas map
      gas_map = %{
        1 => 100,
        2 => 200,
        3 => 300
      }

      # Encode the gas map entries
      encoded_data =
        for {service, value} <- gas_map, into: <<>> do
          e_le(service, 4) <> e_le(value, 8)
        end

      # Write to memory
      memory = %Memory{}
      {:ok, memory} = Memory.write(memory, 0, encoded_data)

      registers = %Registers{
        # manager_service
        r8: 1,
        # alter_authorizer_service
        r9: 2,
        # alter_validator_service
        r10: 3,
        # offset
        r11: 0,
        # count of services
        r12: 3
      }

      {:ok, memory: memory, gas_map: gas_map, registers: registers, gas: 100}
    end

    test "returns OOB when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0, 36, nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.bless(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns WHO when service values are out of range", %{
      memory: memory,
      context: context,
      gas: gas
    } do
      registers = %Registers{
        # Invalid value > 0x100000000
        r8: 0x100000001,
        r9: 2,
        r10: 3,
        r11: 0,
        r12: 3
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.bless(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful bless with valid parameters", %{
      memory: memory,
      context: context,
      gas: gas,
      gas_map: gas_map,
      registers: registers
    } do
      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.bless(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == memory

      # Verify privileged services in context
      expected_privileged = %PrivilegedServices{
        manager_service: 1,
        alter_authorizer_service: 2,
        alter_validator_service: 3,
        services_gas: gas_map
      }

      {x_, y_} = context_
      assert y_ == context |> elem(1)

      assert get_in(x_, [:accumulation, :privileged_services]) == expected_privileged
    end
  end

  describe "assign/4" do
    setup do
      # Setup memory with some test values
      memory = %Memory{}
      # 32-bit test value
      {:ok, memory} = Memory.write(memory, 0, <<1, 2, 3, 4>>)

      {:ok, memory: memory, gas: 100}
    end

    test "returns OOB when memory is not readable", %{context: context, gas: gas} do
      registers = %Registers{
        # value to assign
        r7: 1,
        # offset
        r8: 0
      }

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0, 32, nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.assign(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns CORE when value is too large", %{memory: memory, context: context, gas: gas} do
      registers = %Registers{
        # Value equal to core count
        r7: Constants.core_count(),
        r8: 0
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.assign(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, core())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful assign with valid parameters", %{memory: memory, context: context, gas: gas} do
      registers = %Registers{
        r7: 1,
        r8: 0
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.assign(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == memory

      {x_, y_} = context_
      assert y_ == context |> elem(1)

      # Verify the value was assigned in context
      queue_ = get_in(x_, [:accumulation, :authorizer_queue])
      assert length(Enum.at(queue_, 1)) == Constants.max_authorization_queue_items()
      # asser that all the items are 32 bytes long
      assert Enum.all?(Enum.at(queue_, 1), &(byte_size(&1) == 32))

      <<first_four_bytes::binary-size(4), _::binary>> = Enum.at(Enum.at(queue_, 1), 0)
      assert first_four_bytes == <<1, 2, 3, 4>>
    end
  end

  describe "designate/4" do
    setup do
      memory = %Memory{}

      # Create test data for each validator
      test_data =
        for validator_index <- 0..(Constants.validator_count() - 1),
            into: <<>> do
          # Bandersnatch key (32 bytes)
          # 30 more bytes of zeros
          bandersnatch = <<validator_index, 0>> <> <<0::240>>
          # Ed25519 key (32 bytes)
          # 30 more bytes of zeros
          ed25519 = <<validator_index, 1>> <> <<0::240>>
          # BLS key (144 bytes)
          # 142 more bytes of zeros
          bls = <<validator_index, 2>> <> <<0::1136>>
          # Metadata (128 bytes)
          # 126 more bytes of zeros
          metadata = <<validator_index, 3>> <> <<0::1008>>

          # Concatenate all fields (336 bytes total)
          bandersnatch <> ed25519 <> bls <> metadata
        end

      {:ok, memory} = Memory.write(memory, 0, test_data)

      context = {%Context{}, %Context{}}

      {:ok, memory: memory, context: context, gas: 100}
    end

    test "returns OOB when memory is not readable", %{context: context, gas: gas} do
      registers = %Registers{r7: 0}

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0, 336 * Constants.validator_count(), nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.designate(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful designate with valid parameters", %{
      memory: memory,
      context: context,
      gas: gas
    } do
      registers = %Registers{r7: 0}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.designate(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == memory

      {x_, y_} = context_
      assert y_ == context |> elem(1)

      # Verify the validators were added to context
      validators = get_in(x_, [:accumulation, :next_validators])
      assert length(validators) == Constants.validator_count()

      # Pick 4 random validators to verify
      validators
      |> Enum.with_index()
      |> Enum.take_random(4)
      |> Enum.each(fn {validator, index} ->
        assert %System.State.Validator{
                 bandersnatch: <<^index, 0>> <> _,
                 ed25519: <<^index, 1>> <> _,
                 bls: <<^index, 2>> <> _,
                 metadata: <<^index, 3>> <> _
               } = validator
      end)
    end
  end

  describe "checkpoint/4" do
    test "checkpoints context and updates remaining gas" do
      gas = 100
      # r7 should be overwritten
      registers = %Registers{r1: 1, r7: 42}
      memory = %Memory{}
      # some arbitrary context
      x = %Context{service: 123}
      # different from x
      y = %Context{service: 456}
      context = {x, y}

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.checkpoint(gas, registers, memory, context)

      {_exit_reason, expected_gas} = PVM.Host.Gas.check_gas(gas)
      assert registers_ == Registers.set(registers, :r7, expected_gas)

      assert memory_ == memory

      # Context: second element should equal first, first should be unaltered
      {x_, y_} = context_
      assert x_ == x
      # y is now same as x
      assert y_ == x
    end
  end

  describe "new/4" do
    setup do
      memory = %Memory{}
      # 32-byte code hash
      code_hash = Hash.one()
      {:ok, memory} = Memory.write(memory, 0, code_hash)
      initial_balance = 1000

      # Initial context with service account having more than threshold balance
      service_account = %ServiceAccount{balance: initial_balance}

      context = %Context{
        service: 123,
        # Starting at first valid service index
        computed_service: 0x100,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      {:ok,
       memory: memory, context: {context, context}, gas: 100, initial_balance: initial_balance}
    end

    test "returns OOB when memory is not readable", %{context: context, gas: gas} do
      registers = %Registers{
        # offset
        r7: 0,
        # l
        r8: 1,
        # g
        r9: 100,
        # m
        r10: 200
      }

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0, 32, nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.new(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns CASH when service balance is insufficient", %{
      memory: memory,
      gas: gas
    } do
      service_account = %ServiceAccount{balance: 150}

      context = %Context{
        service: 123,
        computed_service: 124,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      registers = %Registers{
        # offset
        r7: 0,
        # l
        r8: 1,
        # g
        r9: 100,
        # m
        r10: 200
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.new(gas, registers, memory, {context, context})

      assert registers_ == Registers.set(registers, 7, cash())
      assert memory_ == memory
      assert context_ == {context, context}
    end

    test "successful new with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      initial_balance: initial_balance
    } do
      registers = %Registers{
        # offset
        r7: 0,
        # l
        r8: 1,
        # g
        r9: 100,
        # m
        r10: 200
      }

      %Result{registers: registers_, memory: memory_, context: {x_, y_}} =
        Accumulate.new(gas, registers, memory, {x, y})

      assert registers_ == Registers.set(registers, 7, x.computed_service)
      assert memory_ == memory
      assert y_ == y

      # Check computed_service was updated using bump function
      assert x_.computed_service == Utils.check(Utils.bump(x.computed_service), x.accumulation)

      # Check accumulation services were updated
      services = x_.accumulation.services
      prev_service = Map.get(services, x.service)
      new_service = Map.get(services, x.computed_service)

      # Old service should have reduced balance
      assert new_service.balance == ServiceAccount.threshold_balance(new_service)
      assert prev_service.balance == initial_balance - ServiceAccount.threshold_balance(new_service)

      # New service should be created with correct values
      assert new_service.code_hash == Hash.one()
      assert new_service.preimage_storage_l == %{{Hash.one(), 1} => []}
      assert new_service.gas_limit_g == 100
      assert new_service.gas_limit_m == 200
    end
  end

  describe "upgrade/4" do
    setup do
      memory = %Memory{}
      # 32-byte code hash
      code_hash = Hash.one()
      {:ok, memory} = Memory.write(memory, 0, code_hash)

      # Initial service account
      service_account = %ServiceAccount{
        code_hash: <<0::256>>,  # Different from new code hash
        gas_limit_g: 50,        # Different from new gas limit
        gas_limit_m: 100        # Different from new gas limit
      }

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      {:ok,
        memory: memory,
        context: {context, context},
        gas: 100}
    end

    test "returns OOB when memory is not readable", %{context: context, gas: gas} do
      registers = %Registers{
        r7: 0,    # offset
        r8: 200,  # g
        r9: 300   # m
      }

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0, 32, nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.upgrade(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "successful upgrade with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas
    } do
      registers = %Registers{
        r7: 0,    # offset
        r8: 200,  # new gas limit g
        r9: 300   # new gas limit m
      }

      %Result{registers: registers_, memory: memory_, context: {x_, y_}} =
        Accumulate.upgrade(gas, registers, memory, {x, y})

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == memory
      assert y_ == y

      # Check service was updated with new values
      updated_service = get_in(x_, [:accumulation, :services, x.service])
      assert updated_service.code_hash == Hash.one()
      assert updated_service.gas_limit_g == 200
      assert updated_service.gas_limit_m == 300
    end
  end

  describe "transfer/4" do
    setup do
      memory = %Memory{}
      memo = <<1::256>>  # 32-byte memo
      {:ok, memory} = Memory.write(memory, 0, memo)

      # Create service accounts
      sender = %ServiceAccount{
        balance: 500,  # Enough for transfer
        gas_limit_m: 100
      }
      receiver = %ServiceAccount{
        gas_limit_m: 200  # Higher than sender
      }

      context = %Context{
        service: 123,
        transfers: [],
        accumulation: %Accumulation{
          services: %{
            123 => sender,
            456 => receiver
          }
        }
      }

      # Gas calculation: g = 10 + ω8 + 2^32 · ω9
      gas = (10 + 8 + 0x100000000 * 9) * 2

      {:ok,
        memory: memory,
        context: {context, context},
        gas: gas}
    end

    test "returns OOB when memory is not readable", %{context: context, gas: gas} do
      registers = %Registers{
        r7: 456,  # destination
        r8: 100,  # amount
        r9: 150,  # gas limit
        r10: 0    # memo offset
      }

      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0, Constants.memo_size(), nil)

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.transfer(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, oob())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns WHO when destination service doesn't exist", %{
      memory: memory,
      context: context,
      gas: gas
    } do
      registers = %Registers{
        r7: 999,  # non-existent service
        r8: 100,  # amount
        r9: 150,  # gas limit
        r10: 0    # memo offset
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.transfer(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, who())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns LOW when gas limit is less than receiver minimum", %{
      memory: memory,
      context: context,
      gas: gas
    } do
      registers = %Registers{
        r7: 456,  # destination
        r8: 100,  # amount
        r9: 150,  # gas limit < receiver.gas_limit_m (200)
        r10: 0    # memo offset
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.transfer(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, low())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns HIGH when gas limit exceeds available gas", %{
      memory: memory,
      context: context,
      gas: gas
    } do
      registers = %Registers{
        r7: 456,  # destination
        r8: 100,  # amount
        r9: gas * 2,  # gas limit
        r10: 0    # memo offset
      }


      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.transfer(gas, registers, memory, context)

      assert registers_ == Registers.set(registers, 7, high())
      assert memory_ == memory
      assert context_ == context
    end

    test "returns CASH when balance would fall below threshold", %{
      memory: memory,
      context: {x, y},
      gas: gas
    } do
      # Update sender balance to be just above threshold
      sender = get_in(x, [:accumulation, :services, x.service])
      sender = %{sender | balance: ServiceAccount.threshold_balance(sender) + 50}
      x = put_in(x, [:accumulation, :services, x.service], sender)

      registers = %Registers{
        r7: 456,  # destination
        r8: 100,  # amount (would put balance below threshold)
        r9: 250,  # gas limit
        r10: 0    # memo offset
      }

      %Result{registers: registers_, memory: memory_, context: context_} =
        Accumulate.transfer(gas, registers, memory, {x, y})

      assert registers_ == Registers.set(registers, 7, cash())
      assert memory_ == memory
      assert context_ == {x, y}
    end

    test "successful transfer with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas
    } do
      amount = 300
      registers = %Registers{
        r7: 456,    # destination
        r8: amount, # amount
        r9: 250,    # gas limit
        r10: 0      # memo offset
      }

      %Result{registers: registers_, memory: memory_, context: {x_, y_}} =
        Accumulate.transfer(gas, registers, memory, {x, y})

      assert registers_ == Registers.set(registers, 7, ok())
      assert memory_ == memory
      assert y_ == y

      # Check sender's balance was reduced
      sender = get_in(x_, [:accumulation, :services, x.service])
      assert sender.balance == ServiceAccount.threshold_balance(sender) * 2

      # Check transfer was added
      [transfer] = x_.transfers
      assert transfer == %DeferredTransfer{
        sender: x.service,
        receiver: 456,
        amount: amount,
        memo: <<1::256>>,
        gas_limit: gas
      }
    end
  end
end
