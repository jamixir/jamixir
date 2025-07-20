defmodule Network.CertUtils do
  require Logger
  import Bitwise, only: [>>>: 2]

  @ans1prefix <<48, 46, 2, 1, 0, 48, 5, 6, 3, 43, 101, 112, 4, 34, 4, 32>>
  @keyfile Path.join(:code.priv_dir(:jamixir), "secret.pem")
  @certfile Path.join(:code.priv_dir(:jamixir), "cert.pem")
  @ed25519_curve_oid {1, 3, 101, 112}

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

    dns_name = alt_name(public_key)

    cmd = """
      openssl req -new -x509 -days 365 -key #{keyfile} -out #{certfile} -subj "/CN=Jamixir Ed25519 Cert" -addext "subjectAltName=DNS:#{dns_name}"
    """

    System.cmd("sh", ["-c", cmd])
    X509.Certificate.from_pem(File.read!(certfile))
  rescue
    error -> {:error, error}
  end

  def cert_key(private_key, public_key) do
    {:ECPrivateKey, 1, private_key, {:namedCurve, @ed25519_curve_oid}, public_key, :asn1_NOVALUE}
  end

  def valid?(cert) do
    with {:ECPoint, cert_p_key} <- X509.Certificate.public_key(cert),
         {:Extension, _, _, [dNSName: dns_name]} <-
           X509.Certificate.extension(cert, :subject_alt_name),
         true <- to_string(dns_name) == alt_name(cert_p_key) do
      :ok
    else
      _ -> false
    end
  end

  def validate_certificate(cert_der) do
    case :public_key.pkix_decode_cert(cert_der, :otp) do
      {:OTPCertificate, _tbs_cert, _signature_algorithm, _signature} = cert ->
        case X509.Certificate.public_key(cert) do
          # OpenSSL format
          {:ECPoint, ed25519_key} ->
            validate_alternative_name(cert, ed25519_key)

          # X509 library format with curve parameters
          {{:ECPoint, ed25519_key}, {:namedCurve, @ed25519_curve_oid}} ->
            validate_alternative_name(cert, ed25519_key)

          _ ->
            {:error, :not_ed25519_certificate}
        end

      _ ->
        {:error, :invalid_certificate_format}
    end
  rescue
    _ -> {:error, :cert_decode_failed}
  end

  defp validate_alternative_name(cert, ed25519_key) do
    case X509.Certificate.extension(cert, :subject_alt_name) do
      {:Extension, _extn_id, _critical, [dNSName: dns_name]} ->
        if to_string(dns_name) == alt_name(ed25519_key) do
          {:ok, ed25519_key, to_string(dns_name)}
        else
          {:error, :alternative_name_mismatch}
        end

      _ ->
        {:error, :missing_alternative_name}
    end
  end

  @base32_alphabet "abcdefghijklmnopqrstuvwxyz234567"

  def alt_name(k) do
    n = Codec.Decoder.de_le(k, 32)

    "e" <>base32_encode(n, 52)
  end


  defp base32_encode(_n, 0), do: <<>>
  defp base32_encode(n, l), do: String.at(@base32_alphabet, rem(n, 32)) <> base32_encode(n >>> 5, l - 1)
end
