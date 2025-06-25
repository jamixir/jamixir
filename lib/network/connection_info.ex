defmodule Network.ConnectionInfo do
  @moduledoc """
  Structured data for tracking connection state and metadata.
  used by ConnectionManager to track connection state.
  """

  @type status :: :connecting | :connected | :disconnected | :retrying | :waiting_inbound
  @type direction :: :outbound | :inbound

  @type t :: %__MODULE__{
          status: status(),
          direction: direction(),
          retry_count: non_neg_integer(),
          start_time: integer(),
          target: map() | nil
        }

  defstruct status: :connecting,
            direction: :outbound,
            retry_count: 0,
            start_time: System.monotonic_time(:millisecond),
            target: nil
end
