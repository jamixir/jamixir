defmodule PVM.Constants.HostCallId do
  @host_calls {
    :gas,
    :lookup,
    :read,
    :write,
    :info,
    :bless,
    :assign,
    :designate,
    :checkpoint,
    :new,
    :upgrade,
    :transfer,
    :quit,
    :solicit,
    :forget,
    :historical_lookup,
    :import,
    :export,
    :machine,
    :peek,
    :poke,
    :zero,
    :void,
    :invoke,
    :expunge
  }

  def host(code) when code >= 0 and code < tuple_size(@host_calls) do
    elem(@host_calls, code)
  end

  def host(_), do: nil
end
