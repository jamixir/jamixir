defmodule System.Network.Node do
  alias System.Network.CertUtils

  @doc """
  Starts a QUIC server.

  Accepts a `cert_path` for the server certificate, a `key_path` for the server private key, and a `port`.

  It starts a new `JamnpS.Server` task that handles QUIC connections.
  """
  @fixed_opts [
    alpn: [~c"jamnp-s/V/H"],
    versions: [:"tlsv1.3"]
  ]

  @default_opts [
                  certfile: ~c"#{CertUtils.certfile()}",
                  keyfile: ~c"#{CertUtils.keyfile()}"
                ] ++ @fixed_opts

  @default_port 9999

  def fixed_opts, do: @fixed_opts

  def start_server(port \\ @default_port, opts \\ @default_opts) do
    {:ok, pid} = :quicer.listen(port, opts)
    {:ok, pid}
  rescue
    error ->
      IO.puts("Error starting server: #{inspect(error)}")
      error
  end
end
