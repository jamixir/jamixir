defmodule Util.Hex do
  @doc """
  Decodes a hex string that may optionally start with "0x"
  """
  def decode16(hex_str, opts \\ [case: :lower])
  def decode16("0x" <> hex_str, opts), do: Base.decode16(hex_str, opts)
  def decode16(hex_str, opts), do: Base.decode16(hex_str, opts)

  def decode16!(hex_str, opts \\ [case: :lower])
  def decode16!("0x" <> hex_str, opts), do: Base.decode16!(hex_str, opts)
  def decode16!(hex_str, opts), do: Base.decode16!(hex_str, opts)

  def encode16(binary, opts \\ [])

  def encode16(binary, case: casing, prefix: prefix) do
    hex = Base.encode16(binary, case: casing)
    if prefix, do: "0x" <> hex, else: hex
  end

  def encode16(binary, opts) do
    casing = Keyword.get(opts, :case, :lower)
    prefix = Keyword.get(opts, :prefix, false)
    encode16(binary, case: casing, prefix: prefix)
  end
end
