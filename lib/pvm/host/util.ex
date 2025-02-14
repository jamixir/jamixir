defmodule PVM.Host.Util do
  def safe_byte_size(nil), do: 0
  def safe_byte_size(:error), do: 0
  def safe_byte_size(binary), do: byte_size(binary)
end
