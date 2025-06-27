# Formula (7.4) v0.7.0
defmodule System.State.RecentHistory.AccumulationOutput do
  @type t :: %__MODULE__{
          # s
          service: Types.service_index(),
          # b
          accumulated_output: Types.hash()
        }

  defstruct service: nil, accumulated_output: nil
end
