defmodule System.State.RecentHistory.Lastaccout do
  @type t :: %__MODULE__{
          # s
          service: Types.service_index(),
          # b
          accumulated_output: Types.hash()
        }

  defstruct service: nil, accumulated_output: nil
end
