defmodule Network.Config do
  alias Network.CertUtils
  alias Jamixir.Genesis
  import Util.Hex, only: [encode16: 1]
  @protocol_version "0"

  @default_peer_config [
    init_mode: :initiator,
    host: ~c"::1",
    port: 9999,
    timeout: 5_000
  ]

  def quicer_listen_opts(cert_key \\ nil) do
    cert_key_options = get_cert_options(cert_key)
    IO.inspect(cert_key_options)
    # certfile = CertUtils.certfile()
    # keyfile = CertUtils.keyfile()

    cert_key_options ++
      [
        verify: :none,
        alpn: [~c"#{alpn_protocol_identifier()}"],
        peer_bidi_stream_count: Constants.validator_count(),
        peer_unidi_stream_count: 100,
        conn_acceptors: 4,
        # TODO: this is hack to prevent quicer from closing the connection when the peer is not sending any data
        # instead we should intiate up stream and indeed shut dow connection if nothing is moving on them
        # the quicer default is 30 seconds
        idle_timeout_ms: 0
      ]
  end

  def quicer_connect_opts(cert_key \\ nil) do
    cert_key_options = get_cert_options(cert_key)

    cert_key_options ++
      [
        verify: :none,
        alpn: [~c"#{alpn_protocol_identifier()}"],
        idle_timeout_ms: 0
      ]
  end


  def get_cert_options(cert_key \\ nil) do
    cond do
      # Use provided cert_key (useful for tests)
      cert_key != nil ->
        [certkeyasn1: cert_key]

      # # Use PKCS12 binary from memory
      # pkcs12_binary = Application.get_env(:jamixir, :tls_pkcs12_binary) ->
      #   [pkcs12: pkcs12_binary]

      # Fallback to file paths for backward compatibility
      true ->
        certfile = CertUtils.certfile()
        keyfile = CertUtils.keyfile()
        [
          certfile: ~c"#{certfile}",
          keyfile: ~c"#{keyfile}"
        ]
    end
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
