defmodule PVM.Host.General.FetchTest do
  use ExUnit.Case
  alias Block.Extrinsic.{WorkItem, WorkPackage}
  alias PVM.Host.General
  alias PVM.{Memory, Registers, PreMemory}
  alias System.{DeferredTransfer, State.ServiceAccount}
  alias PVM.Accumulate.Operand
  alias Util.Hash
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants, only: [min_allowed_address: 0]
  use Codec.Encoder
  import Constants

  describe "fetch/12" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), 32, :write)
        |> PreMemory.finalize()

      context = %ServiceAccount{}
      gas = 100

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

      n = "encoded_n"
      authorizer_output = "auth_output"
      service_index = 0
      import_segments = [["seg1_1", "seg1_2"], ["seg2_1"]]
      preimages = [["preimage1", "preimage2"], ["preimage3"]]

      operands = [
        %Operand{package_hash: Hash.one(), segment_root: Hash.two(), authorizer: Hash.three(), data: {:ok, "data1"}},
        %Operand{package_hash: Hash.two(), segment_root: Hash.three(), authorizer: Hash.one(), data: {:ok, "data2"}}
      ]

      transfers = [
        %DeferredTransfer{sender: 1, receiver: 2, amount: 100, memo: "memo1"},
        %DeferredTransfer{sender: 2, receiver: 3, amount: 200, memo: "memo2"}
      ]

      # Base registers setup
      registers = %Registers{
        # output address
        r7: min_allowed_address(),
        # offset
        r8: 0,
        # length
        r9: 999,
        # selector
        r10: 0
      }

      {:ok,
       memory: memory,
       context: context,
       gas: gas,
       registers: registers,
       work_package: work_package,
       n: n,
       authorizer_output: authorizer_output,
       service_index: service_index,
       import_segments: import_segments,
       preimages: preimages,
       operands: operands,
       transfers: transfers}
    end

    test "w10 = 0 returns protocol constants", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
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
        max_age_lookup_anchor()::m(timeslot),
        max_authorizations_items()::16-little,
        slot_period()::16-little,
        max_authorization_queue_items()::16-little,
        rotation_period()::16-little,
        max_accumulation_queue_items()::16-little,
        max_extrinsics()::16-little,
        unavailability_period()::16-little,
        validator_count()::16-little,
        max_is_authorized_code_size()::32-little,
        max_work_package_size()::32-little,
        max_service_code_size()::32-little,
        erasure_coded_piece_size()::32-little,
        segment_size()::32-little,
        max_imports()::32-little,
        erasure_coded_pieces_per_segment()::32-little,
        max_work_report_size()::32-little,
        memo_size()::32-little,
        max_exports()::32-little,
        ticket_submission_end()::32-little
      >>

      l = byte_size(expected_constants)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_constants
    end

    test "w10 = 1 returns n when provided", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 1}
      l = byte_size(n)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == n
    end

    test "w10 = 2 returns authorizer output when provided", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 2}
      l = byte_size(authorizer_output)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == authorizer_output
    end

    test "w10 = 3 returns preimage from specified work item", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 3, r11: 0, r12: 1}
      expected_preimage = "preimage2"
      l = byte_size(expected_preimage)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_preimage
    end

    test "w10 = 4 returns preimage from current work item", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 4, r11: 0}
      expected_preimage = "preimage1"
      l = byte_size(expected_preimage)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_preimage
    end

    test "w10 = 5 returns import segment", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 5, r11: 0, r12: 0}
      expected_segment = "seg1_1"
      l = byte_size(expected_segment)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_segment
    end

    test "w10 = 6 returns current import segment", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 6, r11: 1}
      expected_segment = "seg1_2"
      l = byte_size(expected_segment)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_segment
    end

    test "w10 = 7 returns encoded work package", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 7}
      encoded = e(work_package)
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 8 returns encoded authorization code hash and parameterization blob", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 8}
      encoded = e({work_package.authorization_code_hash, vs(work_package.parameterization_blob)})
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 9 returns authorization token", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 9}
      l = byte_size(work_package.authorization_token)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == work_package.authorization_token
    end

    test "w10 = 10 returns encoded refinement context", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 10}
      encoded = e(work_package.context)
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 11 returns encoded work items list", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 11}
      encoded = e(vs(for wi <- work_package.work_items, do: WorkItem.encode_for_fetch_host_call(wi)))
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 12 returns encoded specific work item", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 12, r11: 0}
      encoded = WorkItem.encode_for_fetch_host_call(Enum.at(work_package.work_items, 0))
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 13 returns work item payload", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 13, r11: 1}
      expected_payload = "payload2"
      l = byte_size(expected_payload)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_payload
    end

    test "w10 = 14 returns encoded operands list", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 14}
      encoded = e(vs(operands))
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 15 returns encoded specific operand", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 15, r11: 1}
      encoded = e(Enum.at(operands, 1))
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 16 returns encoded transfers list", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 16}
      encoded = e(vs(transfers))
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 17 returns encoded specific transfer", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 17, r11: 0}
      encoded = e(Enum.at(transfers, 0))
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "returns none when no data found", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      # Invalid selector
      registers = %{registers | r10: 99}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none},
               memory: ^memory,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )
    end

    test "returns none when w10 = 1 but n is nil", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      registers = %{registers | r10: 1}
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none},
               memory: ^memory,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 nil,  # n is nil
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )
    end

    test "panics when memory range check fails", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      # Make memory read-only
      memory = Memory.set_access_by_page(memory, 16, 1, :read)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )
    end

    test "handles partial reads with offset and length", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      # Test partial read with offset and length
      registers = %{registers | r10: 2, r8: 2, r9: 3}  # w10=2 for authorizer_output, offset=2, length=3
      expected_partial = binary_part(authorizer_output, 2, 3)
      l = byte_size(expected_partial)
      v_size = byte_size(authorizer_output)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^v_size},
               memory: memory_,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )

      assert Memory.read!(memory_, registers.r7, l) == expected_partial
    end

    test "handles out of gas condition", %{
      context: context,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      assert %{
               exit_reason: :out_of_gas,
               gas: 0,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } =
               General.fetch(
                 0,  # no gas
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )
    end

    test "handles bounds checking for preimages", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      n: n,
      authorizer_output: authorizer_output,
      service_index: service_index,
      import_segments: import_segments,
      preimages: preimages,
      operands: operands,
      transfers: transfers
    } do
      # Test out of bounds access
      registers = %{registers | r10: 3, r11: 99, r12: 0}  # invalid w11
      none = none()

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^none},
               memory: ^memory,
               context: ^context
             } =
               General.fetch(
                 gas,
                 registers,
                 memory,
                 work_package,
                 n,
                 authorizer_output,
                 service_index,
                 import_segments,
                 preimages,
                 operands,
                 transfers,
                 context
               )
    end
  end
end
