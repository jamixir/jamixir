defmodule Network.CertUtilsTest do
  use ExUnit.Case
  import Bitwise, only: [<<<: 2]
  import Codec.Encoder, only: [e_le: 2]

  alias Network.CertUtils
  alias Util.Hash

  test "invalid certificate dns" do
    {p, k} = :crypto.generate_key(:eddsa, :ed25519)
    cert_key = CertUtils.cert_key(k, p)
    cert = X509.Certificate.self_signed(cert_key, "CN=jamnp-s")

    refute CertUtils.valid?(cert)
  end

  test "invalid certificate algo" do
    {_, k} = :crypto.generate_key(:eddsa, :ed448)
    assert {:error, _} = CertUtils.generate_self_signed_certificate(k)
  end

  describe "PKCS12 extraction utilities" do
    test "extract_from_pkcs12 returns both certificate and private key" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, pkcs12_binary} = CertUtils.generate_self_signed_certificate(private_key)

      case CertUtils.extract_from_pkcs12(pkcs12_binary) do
        {:ok, {cert, extracted_private_key}} ->
          assert CertUtils.valid?(cert)
          # Verify the certificate has the correct public key
          {:ECPoint, cert_pub_key} = X509.Certificate.public_key(cert)
          assert cert_pub_key == public_key
          assert extracted_private_key == private_key

        {:error, reason} ->
          flunk("Failed to extract from PKCS12: #{inspect(reason)}")
      end
    end
  end

  describe "alt_name/1" do
    test "generates 53-character DNS name" do
      key = Hash.zero()
      dns_name = CertUtils.alt_name(key)

      assert byte_size(dns_name) == 53
      assert String.starts_with?(dns_name, "e")
      assert String.length(dns_name) == 53
    end

    test "generates different names for different keys" do
      key1 = Hash.zero()
      key2 = Hash.one()

      dns1 = CertUtils.alt_name(key1)
      dns2 = CertUtils.alt_name(key2)

      assert dns1 != dns2
      assert byte_size(dns1) == 53
      assert byte_size(dns2) == 53
    end
  end

  describe "alt_name/1 engineered key" do
    test "produces ejamixira... for engineered key" do
      # Calculate the integer that produces "jamixir" + 45 'a's
      n =
        9 * (1 <<< 0) + 0 * (1 <<< 5) + 12 * (1 <<< 10) + 8 * (1 <<< 15) + 23 * (1 <<< 20) +
          8 * (1 <<< 25) + 17 * (1 <<< 30)

      key = e_le(n, 32)

      dns = Network.CertUtils.alt_name(key)
      assert dns == "ejamixiraaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    end
  end

  test "handles invalid DER data" do
    invalid_der = <<1, 2, 3, 4, 5>>
    assert {:error, :malformed} = CertUtils.validate_certificate(invalid_der)
  end

  test "rejects certificate without alternative name" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    cert_key = CertUtils.cert_key(private_key, public_key)

    cert = X509.Certificate.self_signed(cert_key, "CN=jamnp-s")
    cert_der = X509.Certificate.to_der(cert)

    assert {:error, :missing_alternative_name} = CertUtils.validate_certificate(cert_der)
  end
end
