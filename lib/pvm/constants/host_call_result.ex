defmodule PVM.Constants.HostCallResult do
  # Apendix B.1
  @none 0xFFFFFFFFFFFFFFFF
  @what 0xFFFFFFFFFFFFFFFE
  @oob 0xFFFFFFFFFFFFFFFD
  @who 0xFFFFFFFFFFFFFFFC
  @full 0xFFFFFFFFFFFFFFFB
  @core 0xFFFFFFFFFFFFFFFA
  @cash 0xFFFFFFFFFFFFFFF9
  @low 0xFFFFFFFFFFFFFFF8
  @huh 0xFFFFFFFFFFFFFFF7
  @ok 0

  def none, do: @none
  def what, do: @what
  def oob, do: @oob
  def who, do: @who
  def full, do: @full
  def core, do: @core
  def cash, do: @cash
  def low, do: @low
  def huh, do: @huh
  def ok, do: @ok
end
