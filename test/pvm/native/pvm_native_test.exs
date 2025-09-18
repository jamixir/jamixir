defmodule Pvm.NativeTest do
  use ExUnit.Case, async: false
  import Pvm.Native
  alias Pvm.Native.ExecuteResult
  import Util.Hex

  test "Rust sends ecall message back to Elixir" do
    # Build program bytes
    host_call_id = 100

    # opcode :ecalli with ID
    program_bytes = <<10, host_call_id>>
    # one trap bit set (0b00000001)
    bitmask_bytes = <<1>>
    prog_length = byte_size(program_bytes)
    program_text = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>
    data = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>
    program_text_size = byte_size(program_text)
    data_size = byte_size(data)
    z = 0
    s = 0
    jump_table_size = 0

    c = <<jump_table_size, z, prog_length>> <> program_bytes <> bitmask_bytes
    c_size = byte_size(c)

    program =
      <<program_text_size::little-24, data_size::little-24, z::little-16, s::little-24,
        program_text::binary, data::binary, c_size::little-32>> <> c

    pc = 0
    gas = 100
    args = <<>>
    mem_ref = memory_new()

    # Call into Rust
    result = execute(program, pc, gas, args, mem_ref)
    IO.puts("Result: #{inspect(result)}")

    # Result from execute should be :waiting
    assert result == %ExecuteResult{used_gas: 1, output: :waiting}

    # Now wait for the Rust side to send us the host call message
    receive do
      {:ecall, host_call_id, state, ^mem_ref} ->
        data = memory_read(mem_ref, 0x10001, 5)
        memory_write(mem_ref, 0x30000, "Hello From Elixir")
        IO.puts("Data: #{inspect(data)}")

        updated_registers = List.replace_at(state.registers, 0, 0x10)
        updated_state = %{state | registers: updated_registers, pc: 2}

        assert is_map(state)
        assert state.registers |> is_list()
        # resume rust side
        final_result = resume(updated_state, mem_ref)
    after
      1000 -> flunk("Did not receive ecall message from Rust")
    end
  end
end
