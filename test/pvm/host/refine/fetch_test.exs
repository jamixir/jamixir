defmodule PVM.Host.Refine.FetchTest do
  use ExUnit.Case
  alias Block.Extrinsic.{WorkItem, WorkPackage}
  alias PVM.Host.Refine
  alias PVM.{Memory, Host.Refine.Context, Registers, PreMemory}
  alias Util.Hash
  import PVM.Constants.HostCallResult
  import PVM.Memory.Constants, only: [min_allowed_address: 0]
  use Codec.Encoder

  describe "fetch/8" do
    setup do
      memory =
        PreMemory.init_nil_memory()
        |> PreMemory.set_access(min_allowed_address(), 32, :write)
        |> PreMemory.finalize()

      context = %Context{}
      gas = 100
      work_item_index = 0

      # Test data
      work_package = %WorkPackage{
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

      authorizer_output = "auth_output"
      import_segments = [["seg1_1", "seg1_2"], ["seg2_1"]]

      preimages = %{
        {Hash.one(), 32} => "preimage1",
        {Hash.two(), 64} => "preimage2",
        {Hash.three(), 9} => "preimage3"
      }

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
       authorizer_output: authorizer_output,
       import_segments: import_segments,
       preimages: preimages,
       work_item_index: work_item_index}
    end

    test "w10 = 0 returns work package", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      encoded = e(work_package)
      l = byte_size(encoded)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == encoded
    end

    test "w10 = 1 returns authorizer output", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      registers = %{registers | r10: 1}
      l = byte_size(authorizer_output)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == authorizer_output
    end

    test "w10 = 2 returns work item payload", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      registers = %{registers | r10: 2, r11: 0}
      l = byte_size("payload1")

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == "payload1"
    end

    test "w10 = 3 returns preimage from work item", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      registers = %{registers | r10: 3, r11: 0, r12: 1}

      preimage_key =
        work_package.work_items
        |> Enum.at(registers.r11)
        |> Map.get(:extrinsic)
        |> Enum.at(registers.r12)

      preimage = Map.get(preimages, preimage_key)
      l = byte_size(preimage)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == preimage
    end

    test "w10 = 4 returns preimage from current work item", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      registers = %{registers | r10: 4, r11: 0}

      preimage_key =
        work_package.work_items
        |> Enum.at(work_item_index)
        |> Map.get(:extrinsic)
        |> Enum.at(registers.r11)

      preimage = Map.get(preimages, preimage_key)
      l = byte_size(preimage)

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == "preimage1"
    end

    test "w10 = 5 returns import segment", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      registers = %{registers | r10: 5, r11: 0, r12: 0}
      l = byte_size("seg1_1")

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == "seg1_1"
    end

    test "w10 = 6 returns current import segment", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      registers = %{registers | r10: 6, r11: 1}
      l = byte_size("seg1_2")

      assert %{
               exit_reason: :continue,
               registers: %{r7: ^l},
               memory: memory_,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )

      assert Memory.read!(memory_, registers.r7, l) == "seg1_2"
    end

    test "returns none when no data found", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
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
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )
    end

    test "panics when memory range check fails", %{
      context: context,
      gas: gas,
      registers: registers,
      memory: memory,
      work_package: work_package,
      work_item_index: work_item_index,
      authorizer_output: authorizer_output,
      import_segments: import_segments,
      preimages: preimages
    } do
      # Make memory read-only
      memory = Memory.set_access_by_page(memory, 16, 1, :read)

      assert %{
               exit_reason: :panic,
               registers: ^registers,
               memory: ^memory,
               context: ^context
             } =
               Refine.fetch(
                 gas,
                 registers,
                 memory,
                 context,
                 work_item_index,
                 work_package,
                 authorizer_output,
                 import_segments,
                 preimages
               )
    end
  end
end
