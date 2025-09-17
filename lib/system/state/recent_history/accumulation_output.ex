# Formula (7.4) v0.7.2
# Formula (12.17) v0.7.2 - B
defmodule System.State.RecentHistory.AccumulationOutput do
  @type t :: %__MODULE__{
          # s
          service: Types.service_index(),
          # h
          accumulated_output: Types.hash()
        }

  defstruct service: nil, accumulated_output: nil
end
