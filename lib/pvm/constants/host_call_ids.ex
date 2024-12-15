defmodule PVM.Constants.HostCallId do
  @host_call_map %{
    1 => :gas,
    2 => :lookup,
    3 => :read,
    4 => :write,
    5 => :info,
    6 => :bless,
    7 => :assign,
    8 => :designate,
    9 => :checkpoint,
    10 => :new_work,
    11 => :upgrade,
    12 => :transfer,
    13 => :quit,
    14 => :solicit,
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
