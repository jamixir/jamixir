defmodule Network.Config do
  alias Network.CertUtils

  @default_peer_config [
    init_mode: :initiator,
    host: ~c"::1",
    port: 9900,
    timeout: 5_000
  ]

  @fixed_quicer_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: Constants.validator_count(),
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none
  ]

  @default_quicer_opts [
                         certfile: ~c"#{CertUtils.certfile()}",
                         keyfile: ~c"#{CertUtils.keyfile()}"
                       ] ++ @fixed_quicer_opts

  @default_stream_opts %{active: true}

  def default_quicer_opts, do: @default_quicer_opts
  def default_peer_config, do: @default_peer_config

  def default_stream_opts, do: @default_stream_opts
end
