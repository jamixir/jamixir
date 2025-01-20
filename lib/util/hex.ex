defmodule Util.Hex do
  @doc """
  Decodes a hex string that may optionally start with "0x"
  """
  def decode16!(hex_str, opts \\ [case: :lower])
  def decode16!("0x" <> hex_str, opts), do: Base.decode16!(hex_str, opts)
  def decode16!(hex_str, opts), do: Base.decode16!(hex_str, opts)
end
