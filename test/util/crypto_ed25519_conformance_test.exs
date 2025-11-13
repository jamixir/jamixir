defmodule Util.Crypto.Ed25519ConformanceTest do
  use ExUnit.Case
  alias Util.Crypto
  import Util.Hex

  @test_vectors_file "test_vectors_ed25519.json"

  describe "Ed25519 ZIP215 conformance" do
    test "loads and validates all 196 test vectors from conformance suite" do
      vectors = load_test_vectors()

      assert length(vectors) == 196, "Expected 196 test vectors"

      for vector <- vectors do
        %{"pk" => pk_hex, "r" => r_hex, "s" => s_hex, "msg" => msg_hex} = vector

        pk = decode16!(pk_hex)
        r = decode16!(r_hex)
        s = decode16!(s_hex)
        msg = decode16!(msg_hex)

        # Signature is R || s (64 bytes total)
        signature = r <> s

        assert Crypto.valid_signature?(signature, msg, pk)
      end
    end

    test "verify current implementation behavior" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      message = "test message"
      signature = Crypto.sign(message, priv)

      assert Crypto.valid_signature?(signature, message, pub),
             "Basic Ed25519 signature verification should work"
    end

    test "test with small-order point (canonical)" do
      pk = <<1>> <> <<0::248>>
      r = <<1>> <> <<0::248>>
      s = <<0::256>>
      msg = "dummy"

      signature = r <> s

      assert Crypto.valid_signature?(signature, msg, pk)
    end

    test "test with non-canonical point encoding" do
      # Non-canonical encoding of point (0, 1): y = 2^255 - 18 instead of y = 1
      # This is y + p where p = 2^255 - 19
      pk =
        <<0xED, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
          0xFF, 0xFF, 0xFF, 0x7F>>

      r = <<1>> <> <<0::248>>
      s = <<0::256>>
      msg = "dummy"

      signature = r <> s

      assert Crypto.valid_signature?(signature, msg, pk)
    end
  end

  defp load_test_vectors do
    Path.join([File.cwd!(), "test", @test_vectors_file])
    |> File.read!()
    |> Jason.decode!()
  end
end
