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
          remote_ed25519_key: Types.ed25519_key(),
          pid: pid() | nil,
          telemetry_event_id: non_neg_integer() | nil
        }

  defstruct status: :connecting,
            direction: :outbound,
            retry_count: 0,
            start_time: System.monotonic_time(:millisecond),
            remote_ed25519_key: nil,
            pid: nil,
            telemetry_event_id: nil
end
