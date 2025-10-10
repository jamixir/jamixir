import Config

config :rustler_precompiled, :force_build, ex_keccak: true
config :jamixir, ecto_repos: [Jamixir.Repo]
config :jamixir, :rpc_port, 19800

import_config "#{Mix.env()}.exs"
