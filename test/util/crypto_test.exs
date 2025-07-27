defmodule Util.CryptoTest do
  use ExUnit.Case
  alias Util.Crypto
  import Util.Hex, only: [b16: 1]

  describe "create_ed25519_key_pair/1" do
    test "correct alice vector" do
      {pub, priv} = Crypto.create_ed25519_key_pair(<<0::256>>)

      assert b16(priv) == "0x996542becdf1e78278dc795679c825faca2e9ed2bf101bf3c4a236d3ed79cf59"
      assert b16(pub) == "0x4418fb8c85bb3985394a8c2756d3643457ce614546202a2f50b093d762499ace"
    end

    test "random seed" do
      seed =
        "f92d680ea3f0ac06307795490d8a03c5c0d4572b5e0a8cffec87e1294855d9d1"
        |> JsonDecoder.from_json()

      {pub, priv} = Crypto.create_ed25519_key_pair(seed)
      assert b16(priv) == "0xf21e2d96a51387f9a7e5b90203654913dde7fa1044e3eba5631ed19f327d6126"
      assert b16(pub) == "0x11a695f674de95ff3daaff9a5b88c18448b10156bf88bc04200e48d5155c7243"
    end
  end

  describe "create_bandersnatch_key_pair/1" do
    test "correct alice vector" do
      {priv, pub} = Crypto.create_bandersnatch_key_pair(<<0::256>>)

      assert b16(pub) == "0xff71c6c03ff88adb5ed52c9681de1629a54e702fc14729f6b50d2f0a76f185b3"
      assert b16(priv) == "0x6137e585dec6e1cd7401ffc8bdfe1400f835a7ddae589ce0ed7b3054e00c9e00"
    end
  end
end
