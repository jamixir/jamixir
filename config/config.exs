import Config

config :rustler_precompiled, :force_build, ex_keccak: true

import_config "#{Mix.env()}.exs"
