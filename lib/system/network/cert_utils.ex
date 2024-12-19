defmodule System.Network.CertUtils do
  alias X509.Certificate.Extension
  require Logger

  @subject_dn "CN=jamnp-s"
  def generate_self_signed_certificate(private_key) do
    {public_key, _} = :crypto.generate_key(:eddsa, :ed25519, private_key)

    cert_key = cert_key(private_key, public_key)

    dns_name = dns_from_public_key(public_key)
    extensions = [subject_alt_name: Extension.subject_alt_name([dns_name])]

    x509_cert =
      X509.Certificate.self_signed(cert_key, @subject_dn, extensions: extensions, hash: :sha256)

    {:ok, x509_cert}
  rescue
    error -> {:error, error}
  end

  def cert_key(private_key, public_key) do
    {:ECPrivateKey, 1, private_key, {:namedCurve, {1, 3, 101, 112}}, public_key, :asn1_NOVALUE}
  end

  def valid?(cert) do
    {{:ECPoint, cert_p_key}, _} = X509.Certificate.public_key(cert)

    {:Extension, _, _, [dNSName: dns_name]} = X509.Certificate.extension(cert, :subject_alt_name)

    to_string(dns_name) == dns_from_public_key(cert_p_key)
  rescue
    _ -> false
  end

  defp dns_from_public_key(k) do
    "e" <> Base.encode32(k, case: :lower)
  end
end
