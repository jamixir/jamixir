defmodule PVM.Constants.HostCallId do
  def gas, do: 1
  def lookup, do: 2
  def read, do: 3
  def write, do: 4
  def info, do: 5
  def bless, do: 6
  def assign, do: 7
  def designate, do: 8
  def checkpoint, do: 9
  def new_work, do: 10
  def upgrade, do: 11
  def transfer, do: 12
  def quit, do: 13
  def solicit, do: 14
  def forge, do: 14
  def historical_lookup, do: 15
  def import, do: 16
  def export, do: 17
  def machine, do: 18
  def peek, do: 19
  def poke, do: 20
  def zero, do: 21
  def void, do: 22
  def invoke, do: 23
  def expunge, do: 24
end
