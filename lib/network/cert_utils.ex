defmodule Network.CertUtils do
  require Logger
  import Bitwise, only: [>>>: 2]

  @ans1prefix <<48, 46, 2, 1, 0, 48, 5, 6, 3, 43, 101, 112, 4, 34, 4, 32>>
  @ed25519_curve_oid {1, 3, 101, 112}

  def generate_self_signed_certificate do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {{public_key, private_key}, generate_self_signed_certificate(private_key)}
  end

  def generate_self_signed_certificate(private_key, opts \\ []) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519, private_key)

    dns_name = alt_name(public_key)

    # Create temporary files for OpenSSL operations
    keyfile = opts[:keyfile] || "/tmp/#{dns_name}_secret.pem"
    certfile = opts[:certfile] || "/tmp/#{dns_name}_cert.pem"
    pkcs12file = opts[:pkcs12file] || "/tmp/#{dns_name}.p12"

    pem = """
    -----BEGIN PRIVATE KEY-----
    #{Base.encode64(@ans1prefix <> private_key)}
    -----END PRIVATE KEY-----
    """


    File.write!(keyfile, pem)

    # Generate certificate using OpenSSL
    cert_cmd = """
      openssl req -new -x509 -days 365 -key #{keyfile} -out #{certfile} -subj "/CN=Jamixir Ed25519 Cert" -addext "subjectAltName=DNS:#{dns_name}"
    """

    case System.cmd("sh", ["-c", cert_cmd]) do
      {_, 0} ->
        # Create PKCS12 bundle
        pkcs12_cmd = """
          openssl pkcs12 -export -out #{pkcs12file} -inkey #{keyfile} -in #{certfile} -passout pass:
        """

        case System.cmd("sh", ["-c", pkcs12_cmd]) do
          {_, 0} ->
            # Read PKCS12 binary
            pkcs12_binary = File.read!(pkcs12file)

            # Clean up temporary files
            File.rm(keyfile)
            File.rm(certfile)
            File.rm(pkcs12file)

            {:ok, pkcs12_binary}

          {error, _} ->
            File.rm(keyfile)
            File.rm(certfile)
            File.rm(pkcs12file)
            {:error, {:pkcs12_creation_failed, error}}
        end

      {error, _} ->
        File.rm(keyfile)
        {:error, {:certificate_creation_failed, error}}
    end
  rescue
    error -> {:error, error}
  end

  def keyfile do
    KeyManager.get_our_ed25519_key()
    |> keyfile()
  end

  def certfile do
    KeyManager.get_our_ed25519_key()
    |> certfile()
  end

  def keyfile(public_key) do
    dns_name = alt_name(public_key)
    "priv/#{dns_name}_secret.pem"
  end

  def certfile(public_key) do
    dns_name = alt_name(public_key)
    "priv/#{dns_name}_cert.pem"
  end

  def ed25519_private_key_asn1(private_key, public_key) do
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
    case X509.Certificate.from_der(cert_der, :OTPCertificate) do
      {:ok, cert} ->
        case X509.Certificate.public_key(cert) do
          # OpenSSL format
          {:ECPoint, ed25519_public_key} ->
            validate_alternative_name(cert, ed25519_public_key)

          # X509 library format with curve parameters
          {{:ECPoint, ed25519_public_key}, {:namedCurve, @ed25519_curve_oid}} ->
            validate_alternative_name(cert, ed25519_public_key)

          _ ->
            {:error, :not_ed25519_certificate}
        end

      error ->
        error
    end
  end

  def extract_from_pkcs12(pkcs12_binary, password \\ "") do
    case {ExFiskal.PKCS12.extract_certs(pkcs12_binary, password),
          ExFiskal.PKCS12.extract_key(pkcs12_binary, password)} do
      {{:ok, cert_pem_with_attrs}, {:ok, key_pem}} ->
        cert_pem = extract_cert_from_bag_attrs(cert_pem_with_attrs)

        case X509.Certificate.from_pem(cert_pem) do
          {:ok, cert} ->
            case extract_private_key_binary(key_pem) do
              {:ok, private_key} ->
                {:ok, {cert, private_key}}

              {:error, reason} ->
                {:error, {:private_key_extraction_failed, reason}}
            end

          {:error, reason} ->
            {:error, {:certificate_parsing_failed, reason}}
        end

      {{:error, reason}, _} ->
        {:error, {:certificate_extraction_failed, reason}}

      {_, {:error, reason}} ->
        {:error, {:private_key_extraction_failed, reason}}
    end
  end

  defp extract_cert_from_bag_attrs(cert_pem_with_attrs) do
    # Find the start of the certificate
    case String.split(cert_pem_with_attrs, "-----BEGIN CERTIFICATE-----") do
      [_bag_attrs, cert_part] ->
        "-----BEGIN CERTIFICATE-----" <> cert_part

      _ ->
        cert_pem_with_attrs
    end
  end

  defp extract_private_key_binary(key_pem) do
    case String.split(key_pem, "-----BEGIN PRIVATE KEY-----") do
      [_header, key_part] ->
        case String.split(key_part, "-----END PRIVATE KEY-----") do
          [key_base64, _footer] ->
            case Base.decode64(String.trim(key_base64)) do
              {:ok, asn1_encoded} ->
                # The ASN.1 encoded private key contains the actual key at the end
                # For Ed25519, it's the last 32 bytes
                if byte_size(asn1_encoded) >= 32 do
                  private_key = binary_part(asn1_encoded, byte_size(asn1_encoded), -32)
                  {:ok, private_key}
                else
                  {:error, :invalid_private_key_size}
                end

              {:error, reason} ->
                {:error, {:base64_decode_failed, reason}}
            end

          _ ->
            {:error, :invalid_private_key_format}
        end

      _ ->
        {:error, :invalid_private_key_format}
    end
  end

  defp validate_alternative_name(cert, ed25519_key) do
    case X509.Certificate.extension(cert, :subject_alt_name) do
      {:Extension, _extn_id, _critical, [dNSName: dns_name]} ->
        if to_string(dns_name) == alt_name(ed25519_key) do
          {:ok, ed25519_key, to_string(dns_name)}
        else
          {:error, :alternative_name_mismatch}
        end

      nil ->
        {:error, :missing_alternative_name}
    end
  end

  @base32_alphabet "abcdefghijklmnopqrstuvwxyz234567"

  def alt_name(k) do
    n = Codec.Decoder.de_le(k, 32)

    "e" <> base32_encode(n, 52)
  end

  defp base32_encode(_n, 0), do: <<>>

  defp base32_encode(n, l),
    do: String.at(@base32_alphabet, rem(n, 32)) <> base32_encode(n >>> 5, l - 1)
end
