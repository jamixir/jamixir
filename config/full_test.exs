import Config

config :jamixir, Jamixir,
  # C
  core_count: 341,
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
  ticket_submission_end: 500

config :logger, level: :none

config :jamixir,
  keys_file: "test/keys/0.json",
  genesis_file: "genesis/genesis.json",
  port: "9900"
