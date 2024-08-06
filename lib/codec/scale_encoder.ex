defmodule ScaleEncoding do
  def encode_integer(value) when value < 0x40 do
    <<value::8>>
  end

  def encode_integer(value) when value < 0x4000 do
    <<value + 0x4000::16-little>>
  end

  def encode_integer(value) when value < 0x40000000 do
    <<value + 0x40000000::32-little>>
  end

  def encode_integer(value) when value < 0x4000000000000000 do
    <<value + 0x4000000000000000::64-little>>
  end

  def encode_integer(_) do
    raise ArgumentError, "Value out of range for decoding"
  end

  def decode_integer(<<value::8>>) when value < 0x40 do
    value
  end

  def decode_integer(<<value::16-little>>) when value >= 0x4000 and value < 0x4000 + 0x4000 do
    value - 0x4000
  end

  def decode_integer(<<value::32-little>>)
      when value >= 0x40000000 and value < 0x40000000 + 0x40000000 do
    value - 0x40000000
  end

  def decode_integer(<<value::64-little>>)
      when value >= 0x4000000000000000 and value < 0x4000000000000000 + 0x4000000000000000 do
    value - 0x4000000000000000
  end

  def decode_integer(_) do
    raise ArgumentError, "Value out of range for decoding"
  end

  # Add more encoding functions as needed
end
