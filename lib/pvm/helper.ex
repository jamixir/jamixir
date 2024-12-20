defmodule PVM.Helper do
  use Codec.Encoder
  alias PVM.Utils.ProgramUtils

  def init(program, bitmask, read_only_memory \\ nil, append_halt \\ true, page_size \\ 32) do
    {program, bitmask} =
      if append_halt do
        ProgramUtils.append_halt(program, bitmask)
      else
        {program, bitmask}
      end

    z = 1
    s = 1
    jump_table = []
    p = <<length(jump_table), z, byte_size(program)>> <> program <> bitmask
    test_pattern = :binary.copy(<<65>>, page_size)

    read = if read_only_memory, do: read_only_memory, else: test_pattern

    e_le(page_size, 3) <>
      e_le(byte_size(read), 3) <>
      e_le(z, 2) <>
      e_le(s, 3) <>
      read <>
      test_pattern <>
      e_le(byte_size(p), 4) <>
      p
  end
end
