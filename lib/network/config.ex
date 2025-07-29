defmodule Network.Config do
  alias Jamixir.Genesis
  import Util.Hex, only: [encode16: 1]
  @protocol_version "0"

  @default_peer_config [
    init_mode: :initiator,
    host: ~c"::1",
    port: 9999,
    timeout: 5_000
  ]

  def common_opts(pkcs12_bundle) do
    [
      pkcs12_bundle: pkcs12_bundle,
      verify: :none,
      alpn: [~c"#{alpn_protocol_identifier()}"],
      # TODO: this is hack to prevent quicer from closing the connection when the peer is not sending any data
      # instead we should intiate up stream and indeed shut dow connection if nothing is moving on them
      # the quicer default is 30 seconds
      idle_timeout_ms: 0
    ]
  end

  def quicer_listen_opts(pkcs12_bundle) do
    common_opts(pkcs12_bundle) ++
      [
        peer_bidi_stream_count: Constants.validator_count(),
        peer_unidi_stream_count: 100,
        conn_acceptors: 4,
        idle_timeout_ms: 0
      ]
  end

  def quicer_connect_opts(pkcs12_bundle) do
    common_opts(pkcs12_bundle)
  end

  @default_stream_opts %{active: true}

  def default_peer_config, do: @default_peer_config

  def default_stream_opts, do: @default_stream_opts

  def alpn_protocol_identifier do
    <<first_8_nibbles::4-binary, _rest::binary>> = Genesis.genesis_header_hash()
    "jamnp-s/#{@protocol_version}/#{encode16(first_8_nibbles)}"
  end

  def alpn_protocol_identifier_builder, do: "#{alpn_protocol_identifier()}/builder"
end
