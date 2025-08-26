import Config

config :jamixir, Jamixir,
  # C
  core_count: 2,
  # D
  forget_delay: 32,
  # E
  epoch_length: 12,
  # K
  max_tickets_pre_extrinsic: 3,
  # N
  tickets_per_validator: 3,
  # P
  slot_period: 6,
  # R
  rotation_period: 4,
  # V
  validator_count: 6,
  # Y
  ticket_submission_end: 10,
  # G_A
  gas_accumulation: 10_000_000,
  # G_T
  gas_total_accumulation: 20_000_000,
  # G_R
  gas_refine: 1_000_000_000

config :logger, level: :debug

config :jamixir, :server_calls, Network.ServerCalls
