# test/system/network/cert_utils_test.exs
defmodule System.Network.CertUtilsTest do
  use ExUnit.Case

  alias System.Network.CertUtils

  describe "create valid certificate" do
    test "generate_self_signed_certificate" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, cert} = CertUtils.generate_self_signed_certificate(private_key)

      {{:ECPoint, cert_p_key}, _} = X509.Certificate.public_key(cert)
      assert cert_p_key == public_key
    end
  end

  describe "valid?/1" do
    test "valid certificate" do
      {_, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {:ok, cert} = CertUtils.generate_self_signed_certificate(private_key)

      assert CertUtils.valid?(cert)
    end

    test "invalid certificate dns" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      cert_key = CertUtils.cert_key(private_key, public_key)
      cert = X509.Certificate.self_signed(cert_key, "CN=jamnp-s", hash: :sha256)

      refute CertUtils.valid?(cert)
    end

    test "invalid certificate algo" do
      {_, private_key} = :crypto.generate_key(:eddsa, :ed448)
      assert {:error, _} = CertUtils.generate_self_signed_certificate(private_key)
    end
  end
end
