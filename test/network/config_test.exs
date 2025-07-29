defmodule Network.ConfigTest do
  use ExUnit.Case
  alias Network.Config
  import Util.Hex, only: [encode16: 1]

  describe "alpn_protocol_identifier/0" do
    test "generates correct protocol identifier format" do
      identifier = Config.alpn_protocol_identifier()

      assert String.starts_with?(identifier, "jamnp-s/0/")
      # "jamnp-s/0/" (10) + 8 hex chars
      assert String.length(identifier) == 18

      hash_part = String.slice(identifier, 10..-1//1)

      assert String.match?(hash_part, ~r/^[0-9a-f]{8}$/)
    end

    test "uses genesis header hash first 8 nibbles" do
      # Get the genesis header hash
      genesis_hash = Jamixir.Genesis.genesis_header_hash()
      <<first_8_nibbles::4-binary, _rest::binary>> = genesis_hash

      identifier = Config.alpn_protocol_identifier()

      assert String.slice(identifier, 10..-1//1) == encode16(first_8_nibbles)
    end
  end

  describe "alpn_protocol_identifier_builder/0" do
    test "adds /builder suffix to base identifier" do
      base_identifier = Config.alpn_protocol_identifier()
      builder_identifier = Config.alpn_protocol_identifier_builder()

      assert builder_identifier == "#{base_identifier}/builder"
    end
  end
end
