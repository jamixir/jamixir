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
  # L
  max_age_lookup_anchor: 24,
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
  gas_refine: 1_000_000_000,
  # W_E
  erasure_coded_piece_size: 4,
  # W_P
  erasure_coded_pieces_per_segment: 1026,
  ignore_refinement_context: true,
  ignore_future_time: true

config :logger, level: :debug

config :jamixir, :server_calls, Network.ServerCalls

# Database path will be resolved at runtime to support releases
# Default to data directory next to the release, or use JAMIXIR_DB_PATH env var
config :jamixir, Jamixir.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: {:system, "JAMIXIR_DB_PATH", "data/jamixir.db"},
  pool_size: 5
