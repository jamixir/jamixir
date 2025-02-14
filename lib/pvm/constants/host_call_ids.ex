defmodule PVM.Constants.HostCallId do
  @host_calls %{
    0 => :gas,
    1 => :lookup,
    2 => :read,
    3 => :write,
    4 => :info,
    5 => :bless,
    6 => :assign,
    7 => :designate,
    8 => :checkpoint,
    9 => :new,
    10 => :upgrade,
    11 => :transfer,
    12 => :eject,
    13 => :query,
    14 => :solicit,
    15 => :forget,
    16 => :yield,
    17 => :historical_lookup,
    18 => :fetch,
    19 => :export,
    20 => :machine,
    21 => :peek,
    22 => :poke,
    23 => :zero,
    24 => :void,
    25 => :invoke,
    26 => :expunge
  }

  for {byte, call} <- @host_calls do
    def from_byte(unquote(byte)), do: unquote(call)
  end

  def from_byte(_), do: nil

  for {byte, call} <- @host_calls do
    def to_byte(unquote(call)), do: unquote(byte)
  end

  def to_byte(_), do: nil

  def host(call) when is_atom(call), do: to_byte(call)
  def host(byte) when is_integer(byte), do: from_byte(byte)
  def host(_), do: nil

  def host_calls, do: @host_calls
end
