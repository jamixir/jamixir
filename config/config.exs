import Config

config :rustler_precompiled, :force_build, ex_keccak: true
config :jamixir, ecto_repos: [Jamixir.Repo]

import_config "#{Mix.env()}.exs"
