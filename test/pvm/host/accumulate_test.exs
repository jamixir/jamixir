defmodule PVM.Host.AccumulateTest do
  use ExUnit.Case
  alias System.DeferredTransfer
  alias System.State.{Accumulation, ServiceAccount, PrivilegedServices}
  alias Util.Hash
  alias PVM.Host.Accumulate

  alias PVM.{
    Memory,
    Host.Accumulate.Context,
    Registers,
    Host.Accumulate.Result,
    Accumulate.Utils,
    PreMemory
  }

  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants, only: [min_allowed_address: 0]
  use Codec.{Encoder, Decoder}

  def a_0, do: PVM.Memory.Constants.min_allowed_address()

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
          <<service::32-little, value::64-little>>
        end

      # Write to memory
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), encoded_data)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      registers = %Registers{
        # privileged_services_service
        r7: 1,
        # authorizer_queue_service
        r8: 2,
        # next_validators_service
        r9: 3,
        # memory offset
        r10: 0x1_0000,
        # count of services
        r11: 3
      }

      {:ok, memory: memory, gas_map: gas_map, registers: registers, gas: 100}
    end

    test "returns {:panic, w7} when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable
      memory = Memory.set_access(%Memory{}, 0x1_000A, 3, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.bless(gas, registers, memory, context)
    end

    test "returns {:continue, who()} when service values are out of bounds", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      registers = %{
        registers
        | r8: 0x1_0000_0000
      }

      who = who()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: ^context
             } = Accumulate.bless(gas, registers, memory, context)
    end

    test "returns {:continue, ok()} with valid parameters", %{
      memory: memory,
      context: context,
      gas: gas,
      gas_map: gas_map,
      registers: registers
    } do
      ok = ok()
      {_x, y} = context

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.bless(gas, registers, memory, context)

      # Verify privileged services in context
      expected_privileged = %PrivilegedServices{
        privileged_services_service: 1,
        authorizer_queue_service: 2,
        next_validators_service: 3,
        services_gas: gas_map
      }

      assert get_in(x_, [:accumulation, :privileged_services]) == expected_privileged
    end
  end

  describe "assign/4" do
    setup do
      # 32-byte test value
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), <<255::256>>)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      context = %Context{
        service: 123,
        accumulation: %Accumulation{}
      }

      registers = %Registers{
        # core to assign
        r7: 1,
        # offset
        r8: 0x1_0000
      }

      {:ok, memory: memory, context: {context, context}, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      # Make memory unreadable
      memory = Memory.set_access(memory, 0x1_0000, 1, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.assign(gas, registers, memory, context)
    end

    test "returns {:continue, core()} when core value is invalid", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      core_count = Constants.core_count()
      core = core()

      registers = %{
        registers
        | r7: core_count + 1
      }

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^core},
               memory: ^memory,
               context: ^context
             } = Accumulate.assign(gas, registers, memory, context)
    end

    test "returns {:continue, ok()} and updates context for valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.assign(gas, registers, memory, {x, y})

      # Verify the authorizer queue was updated in context
      queue = get_in(x_, [:accumulation, :authorizer_queue])
      assert is_list(queue)
      # Core 1 should have the value we wrote to memory
      assert Enum.at(queue, 1) |> List.first() == <<255::256>>
    end
  end

  describe "designate/4" do
    setup do
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

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), test_data)
        |> PreMemory.set_access(a_0(), 336, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      registers = %Registers{r7: 0x1_0000}

      context = {%Context{}, %Context{}}

      {:ok, memory: memory, context: context, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      memory: memory,
      registers: registers
    } do
      memory = Memory.set_access(memory, 0x1_0000, 336, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.designate(gas, registers, memory, context)
    end

    test "returns {:continue, ok()} with valid memory", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.designate(gas, registers, memory, {x, y})

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
      # 32-byte code hash
      code_hash = Hash.one()

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), code_hash)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      # Initial context with service account having more than threshold balance
      service_account = %ServiceAccount{balance: 1000}

      x = %Context{
        service: 123,
        computed_service: 0x100,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      {:ok, memory: memory, context: {x, %Context{}}, gas: 100}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas
    } do
      registers = %Registers{
        # offset
        r7: 0x1_0000,
        # l
        r8: 1,
        # g
        r9: 100,
        # m
        r10: 200
      }

      memory = Memory.set_access(%Memory{}, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.new(gas, registers, memory, context)
    end

    test "returns {:continue, cash()} when service balance is insufficient", %{
      memory: memory,
      gas: gas,
      context: {_x, y}
    } do
      # Create context with low balance service account
      service_account = %ServiceAccount{balance: 150}

      context =
        {%Context{
           service: 123,
           computed_service: 0x100,
           accumulation: %Accumulation{
             services: %{123 => service_account}
           }
         }, y}

      registers = %Registers{
        r7: 0x1_0000,
        r8: 1,
        r9: 100,
        r10: 200
      }

      cash = cash()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^cash},
               memory: ^memory,
               context: ^context
             } = Accumulate.new(gas, registers, memory, context)
    end

    test "returns {:continue, computed_service} and updates context with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas
    } do
      registers = %Registers{
        r7: 0x1_0000,
        r8: 1,
        r9: 100,
        r10: 200
      }

      %{computed_service: computed_service} = x

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^computed_service},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.new(gas, registers, memory, {x, y})

      # Check computed_service was updated
      assert x_.computed_service == Utils.check(Utils.bump(x.computed_service), x.accumulation)

      # Check services were updated correctly
      services = x_.accumulation.services
      prev_service = Map.get(services, x.service)
      new_service = Map.get(services, x.computed_service)

      # Old service should have reduced balance
      assert prev_service.balance == 1000 - ServiceAccount.threshold_balance(new_service)

      # Verify new service properties
      assert new_service == %ServiceAccount{
               code_hash: Hash.one(),
               preimage_storage_l: %{{Hash.one(), 1} => []},
               gas_limit_g: 100,
               gas_limit_m: 200,
               balance: ServiceAccount.threshold_balance(new_service)
             }
    end
  end

  describe "upgrade/4" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), Hash.one())
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      registers = %Registers{
        r7: 0x1_0000,
        r8: 999,
        r9: 1999
      }

      # Initial service account
      service_account = %ServiceAccount{
        code_hash: Hash.three(),
        gas_limit_g: 50,
        gas_limit_m: 100
      }

      x = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      {:ok, memory: memory, context: {x, %Context{}}, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      memory = Memory.set_access(memory, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.upgrade(gas, registers, memory, context)
    end

    test "successful upgrade with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.upgrade(gas, registers, memory, {x, y})

      # Check service was updated with new values
      updated_service = get_in(x_, [:accumulation, :services, x.service])

      assert updated_service == %ServiceAccount{
               code_hash: Hash.one(),
               gas_limit_g: 999,
               gas_limit_m: 1999
             }
    end
  end

  describe "transfer/4" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), <<1::Constants.memo_size()*8>>)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      sender = %ServiceAccount{
        balance: 500,
        gas_limit_m: 100
      }

      receiver = %ServiceAccount{
        # Higher than sender
        gas_limit_m: 200
      }

      x = %Context{
        service: 123,
        transfers: [],
        accumulation: %Accumulation{
          services: %{
            123 => sender,
            456 => receiver
          }
        }
      }

      registers = %Registers{
        # destination
        r7: 456,
        # amount
        r8: sender.balance - 200,
        # gas limit
        r9: 500,
        # memo offset
        r10: 0x1_0000
      }

      {:ok, memory: memory, context: {x, %Context{}}, gas: 1000, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory
    } do
      memory = Memory.set_access(memory, 0x1_0000, 10, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.transfer(gas, registers, memory, context)
    end

    test "returns WHO when destination service doesn't exist", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      registers = %{registers | r7: 999}
      who = who()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: ^context
             } = Accumulate.transfer(gas, registers, memory, context)
    end

    test "returns LOW when gas limit is less than receiver minimum", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      registers = %{registers | r9: 150}
      low = low()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^low},
               memory: ^memory,
               context: ^context
             } = Accumulate.transfer(gas + 100, registers, memory, context)
    end

    test "returns CASH when balance would fall below threshold", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      # Update sender balance to be just above threshold
      sender = x.accumulation.services[x.service]
      sender = %{sender | balance: ServiceAccount.threshold_balance(sender) + 50}
      x = put_in(x, [:accumulation, :services, x.service], sender)

      registers = %{registers | r8: 100, r9: 250}

      cash = cash()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^cash},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.transfer(gas, registers, memory, {x, y})
    end

    test "successful transfer with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      amount = 300
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.transfer(gas + 20, registers, memory, {x, y})

      # Check sender's balance was reduced
      sender = get_in(x_, [:accumulation, :services, x.service])
      assert sender.balance == ServiceAccount.threshold_balance(sender) * 2

      # Check transfer was added
      [transfer] = x_.transfers

      assert transfer == %DeferredTransfer{
               sender: x.service,
               receiver: 456,
               amount: amount,
               memo: <<1::Constants.memo_size()*8>>,
               gas_limit: registers.r9
             }
    end
  end

  describe "eject/4" do
    setup do
      preimage_l_key = {Hash.one(), 50}

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), preimage_l_key |> elem(0))
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      # Service to be ejected
      service_to_eject = %ServiceAccount{
        balance: 500,
        # matches x.service
        code_hash: <<123::32-little>>,
        preimage_storage_l: %{
          # Valid entry with [x,y]
          preimage_l_key => [1, 2]
        }
      }

      initial_service = %ServiceAccount{balance: 1000}

      x = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{
            123 => initial_service,
            456 => service_to_eject
          }
        }
      }

      registers = %Registers{
        # service to eject
        r7: 456,
        # hash offset
        r8: 0x1_0000
      }

      {:ok,
       memory: memory,
       context: {x, %Context{}},
       gas: 100,
       registers: registers,
       timeslot: Constants.forget_delay() + 100,
       preimage_l_key: preimage_l_key}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      memory = Memory.set_access(%Memory{}, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.eject(gas, registers, memory, context, timeslot)
    end

    test "returns {:continue, who()} when service doesn't exist or has wrong code hash", %{
      memory: memory,
      context: context,
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      # Test non-existent service
      registers = %{registers | r7: 999}
      who = who()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: ^context
             } = Accumulate.eject(gas, registers, memory, context, timeslot)

      # Test wrong code hash
      {x, y} = context
      service_wrong_hash = %ServiceAccount{code_hash: <<999::32-little>>}
      x = put_in(x, [:accumulation, :services, 456], service_wrong_hash)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^who},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory, {x, y}, timeslot)
    end

    test "returns {:continue, huh()} when items in storage !=2", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      # this will make items_in_storage != 2
      x = put_in(x, [:accumulation, :services, 456, :storage], %{:key => Hash.five()})
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory, {x, y}, timeslot)
    end

    test "returns {:continue, huh()} {h.l} not in preimage_storage_l", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      memory =
        Memory.set_access_by_page(memory, 16, 1, :write)
        |> Memory.write!(a_0(), Hash.four())
        |> Memory.set_access_by_page(16, 1, :read)

      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory, {x, y}, timeslot)
    end

    test "returns {:continue, huh()} {h.l}  -> ![x,y]", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot,
      preimage_l_key: preimage_l_key
    } do
      # not [x,y]
      x = put_in(x, [:accumulation, :services, 456, :preimage_storage_l, preimage_l_key], [1])
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory, {x, y}, timeslot)
    end

    test "returns {:continue, huh()} {h.l}  -> [x,y], y >= t-D", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot,
      preimage_l_key: preimage_l_key
    } do
      x =
        put_in(x, [:accumulation, :services, 456, :preimage_storage_l, preimage_l_key], [
          1,
          timeslot - Constants.forget_delay() + 10
        ])

      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory, {x, y}, timeslot)
    end

    test "successful eject", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.eject(gas, registers, memory, {x, y}, timeslot)

      # Check service was removed and balance transferred
      refute Map.has_key?(x_.accumulation.services, 456)

      assert Context.accumulating_service(x_).balance ==
               Context.accumulating_service(x).balance +
                 get_in(x, [:accumulation, :services, 456, :balance])
    end
  end

  describe "query/4" do
    setup do
      hash = Hash.one()

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), hash)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      service_account = %ServiceAccount{
        preimage_storage_l: %{
          # Empty list case
          {hash, 1} => [],
          # Single element case
          {hash, 2} => [42],
          # Two element case
          {hash, 3} => [42, 17],
          # Three element case
          {hash, 4} => [42, 17, 99]
        }
      }

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      registers = %Registers{
        r7: 0x1_0000,
        # z value
        r8: 1
      }

      {:ok,
       memory: memory, context: {context, context}, gas: 100, registers: registers, hash: hash}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = Memory.set_access(%Memory{}, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.query(gas, registers, memory, context)
    end

    test "returns {:continue, none()} when key not found", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      # Use z value not in storage
      registers = %{registers | r8: 19}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none, r8: 0},
               memory: ^memory,
               context: ^context
             } = Accumulate.query(gas, registers, memory, context)
    end

    test "returns {:continue, 0, 0} for empty list", %{
      memory: memory,
      context: context,
      gas: gas,
      registers: registers
    } do
      assert %{
               exit_reason: :continue,
               registers: %{r7: 0, r8: 0},
               memory: ^memory,
               context: ^context
             } = Accumulate.query(gas, registers, memory, context)
    end

    test "returns {:continue, 1 + 2^32*x, 0} for [x]", %{
      memory: memory,
      context: {c_x, c_y},
      gas: gas,
      registers: registers,
      hash: hash
    } do
      registers = %{registers | r8: 2}
      [x] = Context.accumulating_service(c_x).preimage_storage_l[{hash, 2}]
      expected_r7 = 1 + 0x1_0000_0000 * x

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^expected_r7, r8: 0},
               memory: ^memory,
               context: {^c_x, ^c_y}
             } = Accumulate.query(gas, registers, memory, {c_x, c_y})
    end

    test "returns {:continue, 2 + 2^32*x, y} for [x,y]", %{
      memory: memory,
      context: {c_x, c_y},
      gas: gas,
      registers: registers,
      hash: hash
    } do
      registers = %{registers | r8: 3}
      [x, y] = Context.accumulating_service(c_x).preimage_storage_l[{hash, 3}]
      expected_r7 = 2 + 0x1_0000_0000 * x

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^expected_r7, r8: ^y},
               memory: ^memory,
               context: {^c_x, ^c_y}
             } = Accumulate.query(gas, registers, memory, {c_x, c_y})
    end

    test "returns {:continue, 3 + 2^32*x, y + 2^32*z} for [x,y,z]", %{
      memory: memory,
      context: {c_x, c_y},
      gas: gas,
      registers: registers,
      hash: hash
    } do
      registers = %{registers | r8: 4}
      [x, y, z] = Context.accumulating_service(c_x).preimage_storage_l[{hash, 4}]
      expected_r7 = 3 + 0x1_0000_0000 * x
      expected_r8 = y + 0x1_0000_0000 * z

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^expected_r7, r8: ^expected_r8},
               memory: ^memory,
               context: {^c_x, ^c_y}
             } = Accumulate.query(gas, registers, memory, {c_x, c_y})
    end
  end

  describe "solicit/5" do
    setup do
      hash = Hash.one()

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), hash)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      # Create service with test cases in preimage_storage_l
      service_account = %ServiceAccount{
        balance: 10000,
        preimage_storage_l: %{
          # Valid [x,y] case
          {hash, 1} => [42, 17],
          # Invalid length case
          {hash, 2} => [1, 2, 3],
          # Invalid empty case
          {hash, 3} => []
        }
      }

      context =
        {%Context{
           service: 123,
           accumulation: %Accumulation{
             services: %{123 => service_account}
           }
         }, %Context{}}

      registers = %Registers{
        # hash offset
        r7: 0x1_0000,
        # z value
        r8: 1
      }

      {:ok, memory: memory, context: context, gas: 100, registers: registers, timeslot: 1000}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      memory = Memory.set_access(%Memory{}, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.solicit(gas, registers, memory, context, timeslot)
    end

    test "returns a_l[{h.z}] -> [] when {h,z} not in storage", %{
      memory: memory,
      context: {c_x, c_y},
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      # Use z value not in storage
      registers = %{registers | r8: 999}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {c_x_, ^c_y}
             } = Accumulate.solicit(gas, registers, memory, {c_x, c_y}, timeslot)

      assert get_in(Context.accumulating_service(c_x_), [:preimage_storage_l, {Hash.one(), 999}]) ==
               []
    end

    test "returns {:continue, huh()} when value not [x,y]", %{
      memory: memory,
      context: context,
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      # Use z value pointing to non [x,y] entries
      # Points to [1,2,3]
      registers = %{registers | r8: 2}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Accumulate.solicit(gas, registers, memory, context, timeslot)

      # Test with empty list
      # Points to []
      registers = %{registers | r8: 3}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Accumulate.solicit(gas, registers, memory, context, timeslot)
    end

    test "returns {:continue, full()} when balance below threshold", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      # Update service to have low balance
      x = put_in(x, [:accumulation, :services, x.service, :balance], 100)
      full = full()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^full},
               memory: ^memory,
               context: {^x, ^y}
             } = Accumulate.solicit(gas, registers, memory, {x, y}, timeslot)
    end

    test "successful solicit with valid parameters", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.solicit(gas, registers, memory, {x, y}, timeslot)

      # Verify timeslot was appended to [x,y]
      updated_storage =
        get_in(x_, [:accumulation, :services, x.service, :preimage_storage_l, {Hash.one(), 1}])

      assert updated_storage == [42, 17, timeslot]
    end
  end

  describe "forget/5" do
    setup do
      hash = Hash.one()

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), hash)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      # Create service with test cases in preimage_storage_l
      service_account = %ServiceAccount{
        preimage_storage_l: %{
          # Empty list case
          {hash, 1} => [],
          # [x,y] case with y < t-D
          {hash, 2} => [42, 17],
          # [x] case
          {hash, 3} => [99],
          # [x,y,w] case with y < t-D
          {hash, 4} => [1, 2, 3],
          # [x,y,w] case with y >= t-D
          {hash, 5} => [1, 999, 3]
        },
        preimage_storage_p: %{hash => "test"}
      }

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      registers = %Registers{
        r7: 0x1_0000,
        r8: 1
      }

      timeslot = Constants.forget_delay() + 100

      {:ok,
       memory: memory,
       context: {context, context},
       gas: 100,
       registers: registers,
       timeslot: timeslot,
       hash: hash}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      memory = Memory.set_access(%Memory{}, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.forget(gas, registers, memory, context, timeslot)
    end

    test "deletes entry and preimage for empty list", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot,
      hash: hash
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory, {x, y}, timeslot)

      x_s_ = Context.accumulating_service(x_)
      refute Map.has_key?(x_s_.preimage_storage_l, {hash, 1})
      refute Map.has_key?(x_s_.preimage_storage_p, hash)
    end

    test "deletes entry and preimage for [x,y] when y < t-D", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      timeslot: timeslot,
      hash: hash,
      registers: registers
    } do
      ok = ok()
      registers = %{registers | r8: 2}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory, {x, y}, timeslot)

      x_s_ = Context.accumulating_service(x_)
      refute Map.has_key?(x_s_.preimage_storage_l, {hash, 2})
      refute Map.has_key?(x_s_.preimage_storage_p, hash)
    end

    test "updates entry to [x,t] for [x]", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      timeslot: timeslot,
      hash: hash,
      registers: registers
    } do
      ok = ok()
      registers = %{registers | r8: 3}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory, {x, y}, timeslot)

      x_s_ = Context.accumulating_service(x_)
      assert x_s_.preimage_storage_l[{hash, 3}] == [99, timeslot]
    end

    test "updates entry to [w,t] for [x,y,w] when y < t-D", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      timeslot: timeslot,
      hash: hash,
      registers: registers
    } do
      ok = ok()
      registers = %{registers | r8: 4}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory, {x, y}, timeslot)

      x_s_ = Context.accumulating_service(x_)
      assert x_s_.preimage_storage_l[{hash, 4}] == [3, timeslot]
    end

    test "returns {:continue, huh()} for invalid cases", %{
      memory: memory,
      context: context,
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      huh = huh()
      # Points to [1,999,3] where 999 >= t-D
      registers = %{registers | r8: 5}

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^huh},
               memory: ^memory,
               context: ^context
             } = Accumulate.forget(gas, registers, memory, context, timeslot)
    end
  end

  describe "yield/4" do
    setup do
      hash = Hash.one()

      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.write(a_0(), hash)
        |> PreMemory.set_access(a_0(), 32, :read)
        |> PreMemory.resolve_overlaps()
        |> PreMemory.finalize()

      context = %Context{
        service: 123,
        accumulation: %Accumulation{},
        # Initially nil
        accumulation_trie_result: nil
      }

      registers = %Registers{
        r7: 0x1_0000
      }

      {:ok, memory: memory, context: {context, context}, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory = Memory.set_access(%Memory{}, 0x1_0000, 32, nil)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } = Accumulate.yield(gas, registers, memory, context)
    end

    test "successful yield updates accumulation_trie_result", %{
      memory: memory,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^ok},
               memory: ^memory,
               context: {x_, ^y}
             } = Accumulate.yield(gas, registers, memory, {x, y})

      # Verify hash was stored in accumulation_trie_result
      assert x_.accumulation_trie_result == Hash.one()
    end
  end
end
