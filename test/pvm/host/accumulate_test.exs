defmodule PVM.Host.AccumulateTest do
  use ExUnit.Case
  alias PVM.Host.Accumulate
  alias System.DeferredTransfer
  alias System.State.{Accumulation, ServiceAccount}
  alias Util.Hash

  alias PVM.{
    Host.Accumulate.Context,
    Registers,
    Host.Accumulate.Result,
    Accumulate.Utils
  }

  import PVM.Constants.HostCallResult
  import Codec.Encoder
  import PVM.Memory.Constants
  import Pvm.Native

  def a_0, do: min_allowed_address()

  setup_all do
    x = %Context{service: 321, accumulation: %Accumulation{manager: 321}}
    {:ok, context: {x, x}}
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
      encoded_always_accumulated =
        for {service, value} <- gas_map, into: <<>> do
          <<service::service(), value::64-little>>
        end

      assigners = for _ <- 1..Constants.core_count(), do: :rand.uniform(255)

      encoded_assigners =
        for service <- assigners, into: <<>> do
          <<service::service()>>
        end

      # Write to memory
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), byte_size(encoded_always_accumulated), 3)
      memory_write(memory_ref, a_0(), encoded_always_accumulated)
      set_memory_access(memory_ref, 2 * a_0(), byte_size(encoded_assigners), 3)
      memory_write(memory_ref, 2 * a_0(), encoded_assigners)

      registers =
        Registers.new(%{
          # manager
          7 => 1,
          # assigners offset
          8 => 2 * a_0(),
          # delegator
          9 => 3,
          # registrar
          10 => 999,
          # memory offset
          11 => 0x1_0000,
          # count of services
          12 => 3
        })

      {:ok,
       memory_ref: memory_ref,
       gas_map: gas_map,
       registers: registers,
       gas: 100,
       assigners: assigners}
    end

    test "returns {:panic, w7} when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable
      memory_ref = build_memory()

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Accumulate.bless(gas, registers, memory_ref, context)
    end

    test "returns {:continue, who()} when service values are out of bounds", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      registers = %{registers | r: put_elem(registers.r, 7, 0x1_0000_0000)}

      who = who()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Accumulate.bless(gas, registers, memory_ref, context)

      assert registers_[7] == who
    end

    test "returns {:continue, ok()} with valid parameters", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      gas_map: gas_map,
      registers: registers,
      assigners: assigners
    } do
      ok = ok()
      {_x, y} = context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.bless(gas, registers, memory_ref, context)

      assert registers_[7] == ok

      # Verify privileged services in context
      expected_privileged = %{
        manager: 1,
        assigners: assigners,
        delegator: 3,
        always_accumulated: gas_map,
        registrar: 999
      }

      assert Map.take(x_.accumulation, [
               :manager,
               :assigners,
               :delegator,
               :always_accumulated,
               :registrar
             ]) ==
               expected_privileged
    end
  end

  describe "assign/4" do
    setup do
      # 32-byte test value
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), <<255::256>>)

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          assigners: [0, 123, 0, 123],
          authorizer_queue: [[Hash.one()], [Hash.two()]]
        }
      }

      registers =
        Registers.new(%{
          # core to assign
          7 => 1,
          # offset
          8 => 0x1_0000
        })

      {:ok, memory_ref: memory_ref, context: {context, context}, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      # Make memory unreadable
      memory_ref = build_memory()

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Accumulate.assign(gas, registers, memory_ref, context)
    end

    test "returns {:continue, huh()} when service != assigners[c]", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      x = elem(context, 0)
      x_ = %{x | service: 999}
      context = {x_, elem(context, 1)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.assign(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end

    test "returns {:continue, core()} when core value is invalid", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      core_count = Constants.core_count()
      core = core()

      registers = %{registers | r: put_elem(registers.r, 7, core_count + 1)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.assign(gas, registers, memory_ref, context)

      assert registers_[7] == core
    end

    test "returns {:continue, ok()} and updates context for valid parameters", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.assign(gas, registers, memory_ref, {x, y})

      assert registers_[7] == ok

      # Verify the authorizer queue was updated in context
      queue = get_in(x_, [:accumulation, :authorizer_queue])
      assigners = get_in(x_, [:accumulation, :assigners])
      assert assigners == [0, 0, 0, 123]
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

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), byte_size(test_data), 3)
      memory_write(memory_ref, a_0(), test_data)

      registers = Registers.new(%{7 => 0x1_0000})

      context = {%Context{service: 123, accumulation: %Accumulation{delegator: 123}}, %Context{}}

      {:ok, memory_ref: memory_ref, context: context, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory_ref = build_memory()

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Accumulate.designate(gas, registers, memory_ref, context)
    end

    test "returns {:continue, huh()} when service != delegator", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      x = elem(context, 0)
      x_ = %{x | service: 999}
      context = {x_, elem(context, 1)}
      huh = huh()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Accumulate.designate(gas, registers, memory_ref, context)

      assert registers_[7] == huh
    end

    test "returns {:continue, ok()} with valid memory", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.designate(gas, registers, memory_ref, {x, y})

      assert registers_[7] == ok

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
      registers = Registers.new(%{1 => 1, 7 => 42})
      memory_ref = build_memory()
      # some arbitrary context
      x = %Context{service: 123}
      # different from x
      y = %Context{service: 456}
      context = {x, y}

      %Result{registers: registers_, context: context_} =
        Accumulate.checkpoint(gas, registers, memory_ref, context)

      {_exit_reason, expected_gas} = PVM.Host.Gas.check_gas(gas)
      assert registers_ == %{registers | r: put_elem(registers.r, 7, expected_gas)}

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

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), code_hash)

      # Initial context with service account having more than threshold balance
      service_account = %ServiceAccount{balance: 1000}

      x = %Context{
        service: 123,
        computed_service: 0x100,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      {:ok, memory_ref: memory_ref, context: {x, %Context{}}, gas: 100}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas
    } do
      registers =
        Registers.new(%{
          # offset
          7 => 0x1_0000,
          # l
          8 => 1,
          # g
          9 => 100,
          # m
          10 => 200
        })

      memory_ref = build_memory()

      timeslot_ = 1

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Accumulate.new(gas, registers, memory_ref, context, timeslot_)
    end

    test "returns {:continue, cash()} when service balance is insufficient", %{
      memory_ref: memory_ref,
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

      registers =
        Registers.new(%{
          7 => 0x1_0000,
          8 => 1,
          9 => 100,
          10 => 200
        })

      cash = cash()
      timeslot_ = 1

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.new(gas, registers, memory_ref, context, timeslot_)

      assert registers_[7] == cash
    end

    test "returns {:continue, computed_service} and updates context with valid parameters", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas
    } do
      registers =
        Registers.new(%{
          7 => 0x1_0000,
          8 => 1,
          9 => 100,
          10 => 200
        })

      %{computed_service: computed_service} = x
      timeslot_ = 1

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.new(gas, registers, memory_ref, {x, y}, timeslot_)

      assert registers_[7] == computed_service
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
               storage: HashedKeysMap.new(%{{Hash.one(), 1} => []}),
               gas_limit_g: 100,
               gas_limit_m: 200,
               balance: ServiceAccount.threshold_balance(new_service),
               deposit_offset: 0,
               creation_slot: timeslot_,
               last_accumulation_slot: 0,
               parent_service: x.service
             }
    end
  end

  describe "upgrade/4" do
    setup do
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), Hash.one())

      registers = Registers.new(%{7 => 0x1_0000, 8 => 999, 9 => 1999})

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

      {:ok, memory_ref: memory_ref, context: {x, %Context{}}, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory_ref = build_memory()

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Accumulate.upgrade(gas, registers, memory_ref, context)
    end

    test "successful upgrade with valid parameters", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: {x_, ^y}} =
               Accumulate.upgrade(gas, registers, memory_ref, {x, y})

      assert registers_[7] == ok

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
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), Constants.memo_size(), 3)
      memory_write(memory_ref, a_0(), <<1::Constants.memo_size()*8>>)

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

      registers =
        Registers.new(%{
          # destination
          7 => 456,
          # amount
          8 => sender.balance - 200,
          # gas limit
          9 => 500,
          # memo offset
          10 => 0x1_0000
        })

      {:ok, memory_ref: memory_ref, context: {x, %Context{}}, gas: 1000, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory_ref = build_memory()

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Accumulate.transfer(gas, registers, memory_ref, context)
    end

    test "returns WHO when destination service doesn't exist", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      registers = %{registers | r: put_elem(registers.r, 7, 999)}
      who = who()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.transfer(gas, registers, memory_ref, context)

      assert registers_[7] == who
    end

    test "returns LOW when gas limit is less than receiver minimum", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      registers = %{registers | r: put_elem(registers.r, 9, 150)}
      low = low()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.transfer(gas + 100, registers, memory_ref, context)

      assert registers_[7] == low
    end

    test "returns CASH when balance would fall below threshold", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      # Update sender balance to be just above threshold
      sender = x.accumulation.services[x.service]
      sender = %{sender | balance: ServiceAccount.threshold_balance(sender) + 50}
      x = put_in(x, [:accumulation, :services, x.service], sender)

      registers = %{registers | r: put_elem(registers.r, 8, 100) |> put_elem(9, 250)}

      cash = cash()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.transfer(gas, registers, memory_ref, {x, y})

      assert registers_[7] == cash
    end

    test "successful transfer with valid parameters", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      amount = 300
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.transfer(gas + 20, registers, memory_ref, {x, y})

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
               gas_limit: registers[9]
             }

      assert registers_[7] == ok
    end
  end

  describe "eject/4" do
    setup do
      preimage_l_key = {Hash.one(), 50}

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), preimage_l_key |> elem(0))

      # Service to be ejected
      service_to_eject = %ServiceAccount{
        balance: 500,
        # matches x.service
        code_hash: <<123::256-little>>,
        storage:
          HashedKeysMap.new(%{
            # Valid entry with [x,y]
            preimage_l_key => [1, 2]
          })
      }

      initial_service = %ServiceAccount{balance: 1000}

      x = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{
            123 => initial_service,
            456 => service_to_eject
          },
          # Initialize authorizer_queue with an empty list
          authorizer_queue: [[]]
        }
      }

      registers =
        Registers.new(%{
          # service to eject
          7 => 456,
          # hash offset
          8 => 0x1_0000
        })

      {:ok,
       memory_ref: memory_ref,
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
      memory_ref = build_memory()

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Accumulate.eject(gas, registers, memory_ref, context, timeslot)
    end

    test "returns {:continue, who()} when service doesn't exist or has wrong code hash", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      # Test non-existent service
      registers = %{registers | r: put_elem(registers.r, 7, 999)}
      who = who()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.eject(gas, registers, memory_ref, context, timeslot)

      assert registers_[7] == who

      # Test wrong code hash
      {x, y} = context
      service_wrong_hash = %ServiceAccount{code_hash: <<999::32-little>>}
      x = put_in(x, [:accumulation, :services, 456], service_wrong_hash)

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == who
    end

    test "returns {:continue, huh()} when items in storage !=2", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      # this will make items_in_storage != 2
      x =
        put_in(
          x,
          [:accumulation, :services, 456, :storage],
          HashedKeysMap.new(%{<<1, 2, 3, 4>> => Hash.five()})
        )

      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == huh
    end

    test "returns {:continue, huh()} {h.l} not in preimage_storage_l", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), Hash.four())

      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == huh
    end

    test "returns {:continue, huh()} {h.l}  -> ![x,y]", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot,
      preimage_l_key: preimage_l_key
    } do
      # not [x,y]
      x = put_in(x, [:accumulation, :services, 456, :storage, preimage_l_key], [1])
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == huh
    end

    test "returns {:continue, huh()} {h.l}  -> [x,y], y >= t-D", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot,
      preimage_l_key: preimage_l_key
    } do
      x =
        put_in(x, [:accumulation, :services, 456, :storage, preimage_l_key], [
          1,
          timeslot - Constants.forget_delay() + 10
        ])

      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.eject(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == huh
    end

    test "successful eject", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.eject(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == ok
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
      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), hash)

      service_account = %ServiceAccount{
        storage:
          HashedKeysMap.new(%{
            # Empty list case
            {hash, 1} => [],
            # Single element case
            {hash, 2} => [42],
            # Two element case
            {hash, 3} => [42, 17],
            # Three element case
            {hash, 4} => [42, 17, 99]
          })
      }

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      registers =
        Registers.new(%{
          7 => 0x1_0000,
          # z value
          8 => 1
        })

      {:ok,
       memory_ref: memory_ref,
       context: {context, context},
       gas: 100,
       registers: registers,
       hash: hash}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory_ref = build_memory()

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Accumulate.query(gas, registers, memory_ref, context)
    end

    test "returns {:continue, none()} when key not found", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      # Use z value not in storage
      registers = %{registers | r: put_elem(registers.r, 8, 19)}
      none = none()

      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Accumulate.query(gas, registers, memory_ref, context)

      assert registers_[7] == none
      assert registers_[8] == 0
    end

    test "returns {:continue, 0, 0} for empty list", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      assert %{exit_reason: :continue, registers: registers_, context: ^context} =
               Accumulate.query(gas, registers, memory_ref, context)

      assert registers_[7] == 0
      assert registers_[8] == 0
    end

    test "returns {:continue, 1 + 2^32*x, 0} for [x]", %{
      memory_ref: memory_ref,
      context: {c_x, c_y},
      gas: gas,
      registers: registers,
      hash: hash
    } do
      registers = %{registers | r: put_elem(registers.r, 8, 2)}
      [x] = Context.accumulating_service(c_x).storage[{hash, 2}]
      expected_r7 = 1 + 0x1_0000_0000 * x

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^c_x, ^c_y}
             } = Accumulate.query(gas, registers, memory_ref, {c_x, c_y})

      assert registers_[7] == expected_r7
      assert registers_[8] == 0
    end

    test "returns {:continue, 2 + 2^32*x, y} for [x,y]", %{
      memory_ref: memory_ref,
      context: {c_x, c_y},
      gas: gas,
      registers: registers,
      hash: hash
    } do
      registers = %{registers | r: put_elem(registers.r, 8, 3)}
      [x, y] = Context.accumulating_service(c_x).storage[{hash, 3}]
      expected_r7 = 2 + 0x1_0000_0000 * x

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^c_x, ^c_y}
             } = Accumulate.query(gas, registers, memory_ref, {c_x, c_y})

      assert registers_[7] == expected_r7
      assert registers_[8] == y
    end

    test "returns {:continue, 3 + 2^32*x, y + 2^32*z} for [x,y,z]", %{
      memory_ref: memory_ref,
      context: {c_x, c_y},
      gas: gas,
      registers: registers,
      hash: hash
    } do
      registers = %{registers | r: put_elem(registers.r, 8, 4)}
      [x, y, z] = Context.accumulating_service(c_x).storage[{hash, 4}]
      expected_r7 = 3 + 0x1_0000_0000 * x
      expected_r8 = y + 0x1_0000_0000 * z

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^c_x, ^c_y}
             } = Accumulate.query(gas, registers, memory_ref, {c_x, c_y})

      assert registers_[7] == expected_r7
      assert registers_[8] == expected_r8
    end
  end

  describe "solicit/5" do
    setup do
      hash = Hash.one()

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), hash)

      # Create service with test cases in preimage_storage_l
      service_account = %ServiceAccount{
        balance: 10_000,
        storage:
          HashedKeysMap.new(%{
            # Valid [x,y] case
            {hash, 1} => [42, 17],
            # Invalid length case
            {hash, 2} => [1, 2, 3],
            # Invalid empty case
            {hash, 3} => []
          })
      }

      context =
        {%Context{
           service: 123,
           accumulation: %Accumulation{
             services: %{123 => service_account}
           }
         }, %Context{}}

      registers =
        Registers.new(%{
          # hash offset
          7 => 0x1_0000,
          # z value
          8 => 1
        })

      {:ok,
       memory_ref: memory_ref, context: context, gas: 100, registers: registers, timeslot: 1000}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      memory_ref = build_memory()

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Accumulate.solicit(gas, registers, memory_ref, context, timeslot)
    end

    test "returns a_l[{h.z}] -> [] when {h,z} not in storage", %{
      memory_ref: memory_ref,
      context: {c_x, c_y},
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      # Use z value not in storage
      registers = %{registers | r: put_elem(registers.r, 8, 999)}
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {c_x_, ^c_y}
             } = Accumulate.solicit(gas, registers, memory_ref, {c_x, c_y}, timeslot)

      assert registers_[7] == ok

      assert get_in(Context.accumulating_service(c_x_), [:storage, {Hash.one(), 999}]) ==
               []
    end

    test "returns {:continue, huh()} when value not [x,y]", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      # Use z value pointing to non [x,y] entries
      # Points to [1,2,3]
      registers = %{registers | r: put_elem(registers.r, 8, 2)}
      huh = huh()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.solicit(gas, registers, memory_ref, context, timeslot)

      assert registers_[7] == huh
      # Test with empty list
      # Points to []
      registers = %{registers | r: put_elem(registers.r, 8, 3)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.solicit(gas, registers, memory_ref, context, timeslot)

      assert registers_[7] == huh
    end

    test "returns {:continue, full()} when balance below threshold", %{
      memory_ref: memory_ref,
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
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.solicit(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == full
    end

    test "successful solicit with valid parameters", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.solicit(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == ok
      # Verify timeslot was appended to [x,y]
      updated_storage =
        get_in(x_, [:accumulation, :services, x.service, :storage, {Hash.one(), 1}])

      assert updated_storage == [42, 17, timeslot]
    end
  end

  describe "forget/5" do
    setup do
      hash = Hash.one()

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), hash)

      # Create service with test cases in preimage_storage_l
      service_account = %ServiceAccount{
        storage:
          HashedKeysMap.new(%{
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
          }),
        preimage_storage_p: %{hash => "test"}
      }

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{123 => service_account}
        }
      }

      registers =
        Registers.new(%{
          7 => 0x1_0000,
          8 => 1
        })

      timeslot = Constants.forget_delay() + 100

      {:ok,
       memory_ref: memory_ref,
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
      memory_ref = build_memory()

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Accumulate.forget(gas, registers, memory_ref, context, timeslot)
    end

    test "deletes entry and preimage for empty list", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      timeslot: timeslot,
      hash: hash
    } do
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == ok
      x_s_ = Context.accumulating_service(x_)
      refute HashedKeysMap.has_key?(x_s_.storage, {hash, 1})
      refute Map.has_key?(x_s_.preimage_storage_p, hash)
    end

    test "deletes entry and preimage for [x,y] when y < t-D", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      timeslot: timeslot,
      hash: hash,
      registers: registers
    } do
      ok = ok()
      registers = %{registers | r: put_elem(registers.r, 8, 2)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == ok
      x_s_ = Context.accumulating_service(x_)
      refute HashedKeysMap.has_key?(x_s_.storage, {hash, 2})
      refute Map.has_key?(x_s_.preimage_storage_p, hash)
    end

    test "updates entry to [x,t] for [x]", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      timeslot: timeslot,
      hash: hash,
      registers: registers
    } do
      ok = ok()
      registers = %{registers | r: put_elem(registers.r, 8, 3)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.forget(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == ok
      x_s_ = Context.accumulating_service(x_)
      assert x_s_.storage[{hash, 3}] == [99, timeslot]
    end

    test "updates entry to [w,t] for [x,y,w] when y < t-D", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      timeslot: timeslot,
      hash: hash,
      registers: registers
    } do
      ok = ok()
      registers = %{registers | r: put_elem(registers.r, 8, 4)}

      assert %{exit_reason: :continue, registers: registers_, context: {x_, ^y}} =
               Accumulate.forget(gas, registers, memory_ref, {x, y}, timeslot)

      assert registers_[7] == ok
      x_s_ = Context.accumulating_service(x_)
      assert x_s_.storage[{hash, 4}] == [3, timeslot]
    end

    test "returns {:continue, huh()} for invalid cases", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      timeslot: timeslot,
      registers: registers
    } do
      huh = huh()
      # Points to [1,999,3] where 999 >= t-D
      registers = %{registers | r: put_elem(registers.r, 8, 5)}

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.forget(gas, registers, memory_ref, context, timeslot)

      assert registers_[7] == huh
    end
  end

  describe "yield/4" do
    setup do
      hash = Hash.one()

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), 32, 3)
      memory_write(memory_ref, a_0(), hash)

      context = %Context{
        service: 123,
        accumulation: %Accumulation{},
        # Initially nil
        accumulation_trie_result: nil
      }

      registers =
        Registers.new(%{
          7 => 0x1_0000
        })

      {:ok, memory_ref: memory_ref, context: {context, context}, gas: 100, registers: registers}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers
    } do
      memory_ref = build_memory()

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               context: ^context
             } = Accumulate.yield(gas, registers, memory_ref, context)
    end

    test "successful yield updates accumulation_trie_result", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers
    } do
      ok = ok()

      assert %{exit_reason: :continue, registers: registers_, context: {x_, ^y}} =
               Accumulate.yield(gas, registers, memory_ref, {x, y})

      assert registers_[7] == ok
      # Verify hash was stored in accumulation_trie_result
      assert x_.accumulation_trie_result == Hash.one()
    end
  end

  describe "provide/5" do
    setup do
      preimage_data = "test_preimage_data"
      hash_of_data = h(preimage_data)

      memory_ref = build_memory()
      set_memory_access(memory_ref, a_0(), byte_size(preimage_data), 3)
      memory_write(memory_ref, a_0(), preimage_data)

      # Service that exists in accumulation
      service_account = %ServiceAccount{
        balance: 1000,
        storage:
          HashedKeysMap.new(%{
            # This preimage already exists
            {hash_of_data, byte_size(preimage_data)} => [42, 17]
          })
      }

      # Service without the preimage
      clean_service = %ServiceAccount{balance: 1000}

      context = %Context{
        service: 123,
        accumulation: %Accumulation{
          services: %{
            123 => service_account,
            456 => clean_service
          },
          # Initialize authorizer_queue with an empty list
          authorizer_queue: [[]]
        },
        preimages: MapSet.new()
      }

      service_index = 456

      registers =
        Registers.new(%{
          7 => service_index,
          8 => a_0(),
          9 => byte_size(preimage_data)
        })

      {:ok,
       memory_ref: memory_ref,
       context: {context, context},
       gas: 100,
       registers: registers,
       service_index: service_index,
       preimage_data: preimage_data,
       hash_of_data: hash_of_data}
    end

    test "returns :panic when memory is not readable", %{
      context: context,
      gas: gas,
      registers: registers,
      service_index: service_index
    } do
      memory_ref = build_memory()

      assert %{exit_reason: :panic, registers: ^registers, context: ^context} =
               Accumulate.provide(gas, registers, memory_ref, context, service_index)
    end

    test "returns {:continue, who()} when service doesn't exist", %{
      memory_ref: memory_ref,
      context: context,
      gas: gas,
      registers: registers
    } do
      # Use service index that doesn't exist in services
      registers = %{registers | r: put_elem(registers.r, 7, 999)}
      service_index = 999
      who = who()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.provide(gas, registers, memory_ref, context, service_index)

      assert registers_[7] == who
    end

    test "returns {:continue, huh()} when preimage already exists in service preimage storage_l",
         %{
           memory_ref: memory_ref,
           context: context,
           gas: gas,
           registers: registers
         } do
      # Use r7 that points to service 123 which has the preimage
      registers = %{registers | r: put_elem(registers.r, 7, 123)}
      huh = huh()
      unused_service_index = 999

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.provide(gas, registers, memory_ref, context, unused_service_index)

      assert registers_[7] == huh
    end

    test "returns {:continue, huh()} when preimage already exists in context preimages", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      preimage_data: preimage_data
    } do
      # Add preimage to context preimages set
      x = %{x | preimages: MapSet.put(x.preimages, {456, preimage_data})}

      # Use r7 that points to service 456 (clean service)
      registers = %{registers | r: put_elem(registers.r, 7, 456)}
      huh = huh()
      unused_service_index = 999

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {^x, ^y}
             } = Accumulate.provide(gas, registers, memory_ref, {x, y}, unused_service_index)

      assert registers_[7] == huh
    end

    test "successful provide with r7 pointing to existing service", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      preimage_data: preimage_data
    } do
      # Use r7 that points to service 456 (clean service)
      registers = %{registers | r: put_elem(registers.r, 7, 456)}
      ok = ok()
      unused_service_index = 999

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.provide(gas, registers, memory_ref, {x, y}, unused_service_index)

      # Verify preimage was added to context
      assert MapSet.member?(x_.preimages, {456, preimage_data})
      assert registers_[7] == ok
    end

    test "successful provide with r7 = max_64_bit_value uses service_index", %{
      memory_ref: memory_ref,
      context: {x, y},
      gas: gas,
      registers: registers,
      preimage_data: preimage_data
    } do
      # Use max 64-bit value to trigger service_index usage
      registers = %{registers | r: put_elem(registers.r, 7, 0xFFFF_FFFF_FFFF_FFFF)}
      # Use service 456 (clean service) as service_index
      service_index = 456
      ok = ok()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: {x_, ^y}
             } = Accumulate.provide(gas, registers, memory_ref, {x, y}, service_index)

      assert registers_[7] == ok
      # Verify preimage was added to context using service_index
      assert MapSet.member?(x_.preimages, {service_index, preimage_data})
    end

    test "returns {:continue, who()} when service_index doesn't exist and r7 = max_64_bit_value",
         %{
           memory_ref: memory_ref,
           context: context,
           gas: gas,
           registers: registers
         } do
      registers = %{registers | r: put_elem(registers.r, 7, 0xFFFF_FFFF_FFFF_FFFF)}
      # Use non-existent service_index
      service_index = 999
      who = who()

      assert %{
               exit_reason: :continue,
               registers: registers_,
               context: ^context
             } = Accumulate.provide(gas, registers, memory_ref, context, service_index)

      assert registers_[7] == who
    end
  end
end
