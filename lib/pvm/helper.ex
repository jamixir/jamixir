defmodule PVM.Helper do
  alias PVM.Utils.ProgramUtils

  @doc """
  allows to start execution from Generic PVM program (https://graypaper.fluffylabs.dev/#/5f542d7/232301232301)
  allows for copy-paste test programs from https://pvm.fluffylabs.dev
  """
  def init_bin(bin, page_size \\ 32) do
    test_pattern = :binary.copy(<<65>>, page_size)
    z = 1
    s = 1

    read = test_pattern

    <<byte_size(read)::24-little, byte_size(test_pattern)::24-little, z::16-little, s::24-little,
      read::binary, test_pattern::binary, byte_size(bin)::32-little, bin::binary>>
  end

  def init(program, bitmask, read_only_memory \\ nil, append_halt \\ true, page_size \\ 32) do
    {program, bitmask} =
      if append_halt do
        ProgramUtils.append_halt(program, bitmask)
      else
        {program, bitmask}
      end

    z = 1
    s = 1
    jump_table = {}

    p =
      PVM.Encoder.encode_program(program, bitmask, jump_table, z)

    test_pattern = :binary.copy(<<65>>, page_size)

    read = if read_only_memory, do: read_only_memory, else: test_pattern

    <<byte_size(read)::24-little, byte_size(test_pattern)::24-little, z::16-little, s::24-little,
      read::binary, test_pattern::binary, byte_size(p)::32-little, p::binary>>
  end
end
