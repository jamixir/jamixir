import Config

config :jamixir, Jamixir,
  # C
  core_count: 341,
  # D
  forget_delay: 19_200,
  # E
  epoch_length: 600,
  # K
  max_tickets_pre_extrinsic: 16,
  # N
  tickets_per_validator: 2,
  # P
  slot_period: 6,
  # R
  rotation_period: 10,
  # V
  validator_count: 1023,
  # Y
  ticket_submission_end: 500,
  # G_A
  gas_accumulation: 10_000_000,
  # G_T
  gas_total_accumulation: 3_500_000_000,
  # G_R
  gas_refine: 5_000_000_000,
  # W_P
  erasure_coded_pieces_per_segment: 6,
  test_env: true

config :logger, level: :none
