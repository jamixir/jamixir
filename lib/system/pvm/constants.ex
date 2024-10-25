defmodule System.PVM.Constants do
  # Apendix B.1

  @none 4_294_967_296 - 1
  @what 4_294_967_296 - 2
  @oob 4_294_967_296 - 3
  @who 4_294_967_296 - 4
  @full 4_294_967_296 - 5
  @core 4_294_967_296 - 6
  @cash 4_294_967_296 - 7
  @low 4_294_967_296 - 8
  @high 4_294_967_296 - 9
  @huh 4_294_967_296 - 10
  @ok 0

  # The return value indicating an item does not exist.
  def none, do: @none
  # Name unknown.
  def what, do: @what

  # The return value for when a memory index is provided for reading/writing which is not accessible.
  def oob, do: @oob
  # Index unknown.
  def who, do: @who
  # Storage full.
  def full, do: @full
  # Core index unknown.
  def core, do: @core
  # Insuﬀicient funds.
  def cash, do: @cash
  # Gas limit too low.
  def low, do: @low
  # Gas limit too high.
  def high, do: @high
  # The item is already solicited or cannot be forgotten.
  def huh, do: @huh
  # The return value indicating general success.
  def ok, do: @ok
end
