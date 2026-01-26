import Config

config :rustler_precompiled, :force_build, ex_keccak: true
config :jamixir, ecto_repos: [Jamixir.Repo]
config :jamixir, :rpc_port, 19800
config :jamixir, Jamixir.Repo, log: false

# Memoize cache configuration - use eviction strategy with bounded memory
config :memoize,
  cache_strategy: Memoize.CacheStrategy.Eviction

config :memoize, Memoize.CacheStrategy.Eviction,
  # Trigger eviction when cache exceeds 500 MB
  max_threshold: 500 * 1024 * 1024,
  # Evict down to 200 MB
  min_threshold: 200 * 1024 * 1024

import_config "#{Mix.env()}.exs"
