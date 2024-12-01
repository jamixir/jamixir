defmodule PVM.Constants.InnerPVMResult do
  # Apendix B.1
  @halt 0
  @panic 1
  @fault 2
  @host 3
  @oog 4

  def halt, do: @halt
  def panic, do: @panic
  def fault, do: @fault
  def host, do: @host
  def oog, do: @oog
end
