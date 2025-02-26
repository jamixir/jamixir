defmodule PVM.Utils.AddInstruction do
  import Bitwise

  @moduledoc """
  Utilities for manipulating PVM program binaries and bitmasks.
  """

  @doc """
  Inserts an instruction with its bitmask at a specified position in a program binary.

  ## Parameters
    - program: The original program binary as a list of bytes
    - length_index: Index where the program length is stored (typically 2)
    - instruction: The instruction bytes to insert
    - bitmask: The bitmask bits to insert (as a list of 1s and 0s)
    - insert_at: Position in the program code where to insert (0 means beginning of program code)

  ## Returns
    The updated program binary with the instruction and bitmask inserted
  """
  def insert_instruction(program, length_index, instruction, bitmask_to_insert, insert_at \\ 0)
      when is_list(program) do
    # Get the current program length
    program_length = Enum.at(program, length_index)
    program_start = length_index + 1

    # Split the program into parts
    {prefix, rest} = Enum.split(program, program_start)
    {program_code, bitmask} = Enum.split(rest, program_length)

    # Split program code at insertion point
    {code_prefix, code_suffix} = Enum.split(program_code, insert_at)

    # Convert bitmask section to bits, insert new bits, and convert back to bytes
    bitmask_bytes = Enum.take(bitmask, ceil(program_length / 8))
    bitmask_bits = bitmask_bytes_to_bits(bitmask_bytes)

    # Split bitmask bits at insertion point
    {mask_prefix, mask_suffix} = Enum.split(bitmask_bits, insert_at)

    # Insert instruction and bitmask at specified position
    new_program_code = code_prefix ++ instruction ++ code_suffix
    new_bitmask_bits = mask_prefix ++ bitmask_to_insert ++ mask_suffix

    # Only take the bits we need (one bit per byte of program)
    new_bitmask_bits = Enum.take(new_bitmask_bits, program_length + length(instruction))

    # Pad bitmask bits to multiple of 8
    padded_bitmask_bits = pad_bits(new_bitmask_bits)

    # Convert back to bytes
    new_bitmask_bytes = bits_to_bytes(padded_bitmask_bits)

    # Update program length
    new_length = program_length + length(instruction)

    # Reconstruct the program
    prefix = List.replace_at(prefix, length_index, new_length)

    # Convert the final list to binary
    :binary.list_to_bin(prefix ++ new_program_code ++ new_bitmask_bytes)
  end

  @doc """
  Converts a list of bytes into a list of bits, with each byte's bits in LSB order
  """
  def bitmask_bytes_to_bits(bytes) do
    bytes
    |> Enum.flat_map(fn byte ->
      0..7
      |> Enum.map(fn bit_pos ->
        (byte &&& 1 <<< bit_pos) >>> bit_pos
      end)
    end)
  end

  @doc """
  Pads a list of bits to a multiple of 8 by adding 0s at the end, but only if needed
  """
  def pad_bits(bits) do
    case rem(length(bits), 8) do
      0 -> bits  # If already a multiple of 8, don't add padding
      n -> bits ++ List.duplicate(0, 8 - n)
    end
  end

  @doc """
  Converts a list of bits into bytes, taking bits in groups of 8 and treating them as LSB order
  """
  def bits_to_bytes(bits) do
    bits
    |> Enum.chunk_every(8)
    |> Enum.map(fn byte_bits ->
      byte_bits
      |> Enum.with_index()
      |> Enum.reduce(0, fn {bit, idx}, acc ->
        acc + (bit <<< idx)
      end)
    end)
  end
end
