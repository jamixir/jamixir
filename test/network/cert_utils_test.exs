# test/system/network/cert_utils_test.exs
defmodule Network.CertUtilsTest do
  use ExUnit.Case

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

  def script do
    {p, k} = :crypto.generate_key(:eddsa, :ed25519, Hash.zero())
    {:ok, cert} = CertUtils.generate_self_signed_certificate(k)
    cert_key = CertUtils.cert_key(k, p)
    IO.puts(X509.PrivateKey.to_pem(cert_key))
    IO.puts(X509.Certificate.to_pem(cert))
  end
end
