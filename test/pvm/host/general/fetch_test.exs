defmodule PVM.Host.General.FetchTest do
  use ExUnit.Case
  alias Block.Extrinsic.{WorkItem, WorkPackage}
  alias PVM.Accumulate.Operand
  alias PVM.Host.{General, General.FetchArgs}
  alias PVM.{Memory, PreMemory, Registers}
  alias System.{DeferredTransfer, State.ServiceAccount}
  alias Util.Hash
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants, only: [min_allowed_address: 0]
  import Codec.Encoder
  import Constants

  describe "fetch/12" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), 32, :write)
        |> PreMemory.finalize()

      # Test data
      work_package = %WorkPackage{
        authorization_code_hash: Hash.one(),
        parameterization_blob: "param_blob",
        authorization_token: "auth_token",
        context: %RefinementContext{
          timeslot: 42,
          anchor: Hash.one(),
          state_root: Hash.two(),
          beefy_root: Hash.three(),
          lookup_anchor: Hash.one()
        },
        work_items: [
          %WorkItem{
            payload: "payload1",
            extrinsic: [{Hash.one(), 32}, {Hash.two(), 64}]
          },
          %WorkItem{
            payload: "payload2",
            extrinsic: [{Hash.three(), 9}]
          }
        ]
      }

      operands = [
        %Operand{
          package_hash: Hash.one(),
          segment_root: Hash.two(),
          authorizer: Hash.three(),
          data: {:ok, "data1"}
        },
        %Operand{
          package_hash: Hash.two(),
          segment_root: Hash.three(),
          authorizer: Hash.one(),
          data: {:ok, "data2"}
        }
      ]

      registers =
        Registers.new(%{
          # output address
          7 => min_allowed_address(),
          # offset
          8 => 0,
          # length
          9 => 999,
          # selector
          10 => 0
        })

      args = %FetchArgs{
        gas: 100,
        registers: registers,
        memory: memory,
        work_package: work_package,
        n: "encoded_n",
        authorizer_trace: "auth_output",
        index: 0,
        import_segments: [["seg1_1", "seg1_2"], ["seg2_1"]],
        preimages: [["preimage1", "preimage2"], ["preimage3"]],
        operands: operands,
        transfers: [
          %DeferredTransfer{sender: 1, receiver: 2, amount: 100, memo: "memo1"},
          %DeferredTransfer{sender: 2, receiver: 3, amount: 200, memo: "memo2"}
        ],
        context: %ServiceAccount{}
      }

      {:ok, %{args: args}}
    end

    test "w10 = 0 returns protocol constants", %{
      args: args
    } do
      expected_constants = <<
        additional_minimum_balance_per_item()::m(balance),
        additional_minimum_balance_per_octet()::m(balance),
        service_minimum_balance()::m(balance),
        core_count()::m(core_index),
        forget_delay()::m(timeslot),
        epoch_length()::m(epoch),
        gas_accumulation()::m(gas),
        gas_is_authorized()::m(gas),
        gas_refine()::m(gas),
        gas_total_accumulation()::m(gas),
        recent_history_size()::16-little,
        max_work_items()::16-little,
        max_work_report_dep_sum()::16-little,
        max_tickets_pre_extrinsic()::16-little,
        max_age_lookup_anchor()::m(timeslot),
        tickets_per_validator()::16-little,
        max_authorizations_items()::16-little,
        slot_period()::16-little,
        max_authorization_queue_items()::16-little,
        rotation_period()::16-little,
        max_extrinsics()::16-little,
        unavailability_period()::16-little,
        validator_count()::16-little,
        max_is_authorized_code_size()::32-little,
        max_work_package_size()::32-little,
        max_service_code_size()::32-little,
        erasure_coded_piece_size()::32-little,
        max_imports()::32-little,
        erasure_coded_pieces_per_segment()::32-little,
        max_work_report_size()::32-little,
        memo_size()::32-little,
        max_exports()::32-little,
        ticket_submission_end()::32-little
      >>

      l = byte_size(expected_constants)
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 0)}}
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_constants
      assert registers_[7] == l
    end

    test "w10 = 1 returns n when provided", %{
      args: args
    } do
      l = byte_size(args.n)
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 1)}}
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == args.n
      assert registers_[7] == l
    end

    test "w10 = 2 returns authorizer output when provided", %{
      args: args
    } do
      l = byte_size(args.authorizer_trace)
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 2)}}
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == args.authorizer_trace
      assert registers_[7] == l
    end

    test "w10 = 3 returns preimage from specified work item", %{
      args: args
    } do
      args = %{
        args
        | registers: %{
            args.registers
            | r: put_elem(args.registers.r, 10, 3) |> put_elem(11, 0) |> put_elem(12, 1)
          }
      }

      expected_preimage = args.preimages |> Enum.at(0) |> Enum.at(1)
      l = byte_size(expected_preimage)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_preimage
      assert registers_[7] == l
    end

    test "w10 = 4 returns preimage from current work item", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 4) |> put_elem(11, 0)}}
      expected_preimage = args.preimages |> Enum.at(args.index) |> Enum.at(0)
      l = byte_size(expected_preimage)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_preimage
      assert registers_[7] == l
    end

    test "w10 = 5 returns import segment", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 5) |> put_elem(11, 0) |> put_elem(12, 0)}}
      expected_segment = args.import_segments |> Enum.at(0) |> Enum.at(0)
      l = byte_size(expected_segment)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_segment
      assert registers_[7] == l
    end

    test "w10 = 6 returns current import segment", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 6) |> put_elem(11, 1)}}
      expected_segment = args.import_segments |> Enum.at(args.index) |> Enum.at(1)
      l = byte_size(expected_segment)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_segment
      assert registers_[7] == l
    end

    test "w10 = 7 returns encoded work package", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 7)}}
      encoded = e(args.work_package)
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 8 returns encoded authorization code hash and parameterization blob", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 8)}}

      encoded =
        e(
          {args.work_package.authorization_code_hash, vs(args.work_package.parameterization_blob)}
        )

      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 9 returns authorization token", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 9)}}
      l = byte_size(args.work_package.authorization_token)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == args.work_package.authorization_token
      assert registers_[7] == l
    end

    test "w10 = 10 returns encoded refinement context", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 10)}}
      encoded = e(args.work_package.context)
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 11 returns encoded work items list", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 11)}}

      encoded =
        e(vs(for wi <- args.work_package.work_items, do: WorkItem.encode(wi, :fetch_host_call)))

      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 12 returns encoded specific work item", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 12) |> put_elem(11, 0)}}
      encoded = WorkItem.encode(Enum.at(args.work_package.work_items, 0), :fetch_host_call)
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 13 returns work item payload", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 13) |> put_elem(11, 1)}}
      expected_payload = args.work_package.work_items |> Enum.at(1) |> Map.get(:payload)
      l = byte_size(expected_payload)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_payload
      assert registers_[7] == l
    end

    test "w10 = 14 returns encoded operands list", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 14)}}
      encoded = e(vs(args.operands))
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 15 returns encoded specific operand", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 15) |> put_elem(11, 1)}}
      encoded = e(Enum.at(args.operands, 1))
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
      end

    test "w10 = 16 returns encoded transfers list", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 16)}}
      encoded = e(vs(args.transfers))
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "w10 = 17 returns encoded specific transfer", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 17) |> put_elem(11, 0)}}
      encoded = e(Enum.at(args.transfers, args.registers[11]))
      l = byte_size(encoded)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == encoded
      assert registers_[7] == l
    end

    test "returns none when no data found", %{
      args: args
    } do
      # Invalid selector
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 99)}}
      none = none()
      context = args.context
      memory = args.memory

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } =
               General.fetch(args)

      assert registers_[7] == none
    end

    test "returns none when w10 = 1 but n is nil", %{
      args: args
    } do
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 1)}, n: nil}
      none = none()
      context = args.context
      memory = args.memory

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } =
               General.fetch(args)

      assert registers_[7] == none
    end

    test "panics when memory range check fails", %{
      args: args
    } do
      # Make memory read-only
      memory_ = Memory.set_access_by_page(args.memory, 16, 1, :read)
      args = %{args | memory: memory_}
      context = args.context
      registers = args.registers

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory_,
               context: ^context
             } =
               General.fetch(args)
    end

    test "handles partial reads with offset and length", %{
      args: args
    } do
      # Test partial read with offset and length
      # w10=2 for authorizer_output, offset=2, length=3
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 2) |> put_elem(8, 2) |> put_elem(9, 3)}}
      expected_partial = binary_part(args.authorizer_trace, 2, 3)
      l = byte_size(expected_partial)
      v_size = byte_size(args.authorizer_trace)
      context = args.context

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: memory_,
               context: ^context
             } =
               General.fetch(args)

      assert Memory.read!(memory_, args.registers[7], l) == expected_partial
      assert registers_[7] == v_size
    end

    test "handles out of gas condition", %{
      args: args
    } do
      args = %{args | gas: 0}
      context = args.context
      registers = args.registers
      memory = args.memory

      assert %{
               exit_reason: :out_of_gas,
               gas: 0,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } =
               General.fetch(args)
    end

    test "handles bounds checking for preimages", %{
      args: args
    } do
      # Test out of bounds access
      # invalid w11
      args = %{args | registers: %{args.registers | r: put_elem(args.registers.r, 10, 3) |> put_elem(11, 99) |> put_elem(12, 0)}}
      none = none()
      context = args.context
      memory = args.memory

      assert %{
               exit_reason: :continue,
               registers: registers_,
               memory: ^memory,
               context: ^context
             } =
               General.fetch(args)

      assert registers_[7] == none
    end
  end
end
