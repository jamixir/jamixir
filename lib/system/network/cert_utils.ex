defmodule System.Network.CertUtils do
  require Logger

  @ans1prefix <<48, 46, 2, 1, 0, 48, 5, 6, 3, 43, 101, 112, 4, 34, 4, 32>>
  @keyfile "priv/secret.pem"
  @certfile "priv/cert.pem"

  def keyfile, do: @keyfile
  def certfile, do: @certfile

  def generate_self_signed_certificate do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {{public_key, private_key}, generate_self_signed_certificate(private_key)}
  end

  def generate_self_signed_certificate(private_key, opts \\ []) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519, private_key)

    keyfile = opts[:keyfile] || @keyfile
    certfile = opts[:certfile] || @certfile

    pem = """
    -----BEGIN PRIVATE KEY-----
    #{Base.encode64(@ans1prefix <> private_key)}
    -----END PRIVATE KEY-----
    """

    File.rm(keyfile)
    File.write!(keyfile, pem)
    File.rm(certfile)

    dns_name = dns_from_public_key(public_key)

    cmd = """
      openssl req -new -x509 -days 365 -key #{keyfile} -out #{certfile} -subj "/CN=Jamixir Ed25519 Cert" -addext "subjectAltName=DNS:#{dns_name}"
    """

    System.cmd("sh", ["-c", cmd])
    X509.Certificate.from_pem(File.read!(certfile))
  rescue
    error -> {:error, error}
  end

  def cert_key(private_key, public_key) do
    {:ECPrivateKey, 1, private_key, {:namedCurve, {1, 3, 101, 112}}, public_key, :asn1_NOVALUE}
  end

  def valid?(cert) do
    with {:ECPoint, cert_p_key} <- X509.Certificate.public_key(cert),
         {:Extension, _, _, [dNSName: dns_name]} <-
           X509.Certificate.extension(cert, :subject_alt_name),
         true <- to_string(dns_name) == dns_from_public_key(cert_p_key) do
      :ok
    else
      _ -> false
    end
  end

  defp dns_from_public_key(k) do
    "e" <> Base.encode32(k, case: :lower)
  end
end
