defmodule Network.Config do
  alias Network.CertUtils

  @default_peer_config [
    init_mode: :initiator,
    host: ~c"::1",
    port: 9999,
    timeout: 5_000
  ]

  @fixed_quicer_opts [
    alpn: [~c"jamnp-s/V/H"],
    peer_bidi_stream_count: Constants.validator_count(),
    peer_unidi_stream_count: 100,
    versions: [:"tlsv1.3"],
    verify: :none,
    conn_acceptors: 4,
    # TODO: this is hack to prevent quicer from closing the connection when the peer is not sending any data
    # instead we shoudl intiate up stream and indeed shut dow connection if nothing is moving on them
    # the quicer default is 30 seconds
    idle_timeout_ms: 0
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
