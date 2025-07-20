# test/system/network/cert_utils_test.exs
defmodule Network.CertUtilsTest do
  use ExUnit.Case
  import Bitwise, only: [<<<: 2]
  import Codec.Encoder, only: [e_le: 2]

  alias Network.CertUtils
  alias Util.Hash

  describe "create valid certificate" do
    test "generate_self_signed_certificate" do
      {p, k} = :crypto.generate_key(:eddsa, :ed25519)

      {:ok, cert} = CertUtils.generate_self_signed_certificate(k)

      {:ECPoint, cert_p_key} = X509.Certificate.public_key(cert)
      assert cert_p_key == p
    end
  end

  describe "valid?/1" do
    test "valid certificate" do
      {_, k} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, cert} = CertUtils.generate_self_signed_certificate(k)

      assert CertUtils.valid?(cert)
    end

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

  describe "extract_ed25519_key_from_certificate/1" do
    test "extracts ed25519 key from valid certificate" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, cert} = CertUtils.generate_self_signed_certificate(private_key)
      alt_name = CertUtils.alt_name(public_key)

      # Convert certificate to DER format
      cert_der = X509.Certificate.to_der(cert)

      # Extract and validate
      assert {:ok, ^public_key, ^alt_name} = CertUtils.validate_certificate(cert_der)
    end

    test "handles invalid DER data" do
      invalid_der = <<1, 2, 3, 4, 5>>
      assert {:error, :cert_decode_failed} = CertUtils.validate_certificate(invalid_der)
    end

    test "rejects certificate without alternative name" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      cert_key = CertUtils.cert_key(private_key, public_key)

      # Create certificate without alternative name extension
      cert = X509.Certificate.self_signed(cert_key, "CN=jamnp-s")
      cert_der = X509.Certificate.to_der(cert)

      # Should fail because no alternative name extension
      assert {:error, :missing_alternative_name} = CertUtils.validate_certificate(cert_der)
    end
  end

  def script do
    {p, k} = :crypto.generate_key(:eddsa, :ed25519, Hash.zero())
    {:ok, cert} = CertUtils.generate_self_signed_certificate(k)
    cert_key = CertUtils.cert_key(k, p)
    IO.puts(X509.PrivateKey.to_pem(cert_key))
    IO.puts(X509.Certificate.to_pem(cert))
  end
end
