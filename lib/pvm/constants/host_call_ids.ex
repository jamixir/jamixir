defmodule PVM.Constants.HostCallId do
  @host_calls %{
    0 => :gas,
    1 => :fetch,
    2 => :lookup,
    3 => :read,
    4 => :write,
    5 => :info,
    6 => :historical_lookup,
    7 => :export,
    8 => :machine,
    9 => :peek,
    10 => :poke,
    11 => :pages,
    12 => :invoke,
    13 => :expunge,
    14 => :bless,
    15 => :assign,
    16 => :designate,
    17 => :checkpoint,
    18 => :new,
    19 => :upgrade,
    20 => :transfer,
    21 => :eject,
    22 => :query,
    23 => :solicit,
    24 => :forget,
    25 => :yield,
    26 => :provide,
    100 => :log
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
