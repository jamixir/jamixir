defmodule PVM.Constants.HostCallId do
  @host_call_map %{
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
    12 => :quit,
    13 => :solicit,
    14 => :forget,
    15 => :historical_lookup,
    16 => :import,
    17 => :export,
    18 => :machine,
    19 => :peek,
    20 => :poke,
    21 => :zero,
    22 => :void,
    23 => :invoke,
    24 => :expunge
  }

  def host(code) do
    Map.get(@host_call_map, code)
  end
end
