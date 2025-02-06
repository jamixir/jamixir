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

  def host(code) when is_integer(code) do
    Map.get(@host_calls, code)
  end

  def host(_), do: nil
end
