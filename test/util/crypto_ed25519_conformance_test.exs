defmodule Util.Crypto.Ed25519ConformanceTest do
  @moduledoc """
  Tests Ed25519 signature verification against ZIP215 consensus-critical test vectors.

  These tests verify compliance with the ed25519-consensus requirements:
  https://github.com/davxy/jam-conformance/tree/ed25519-consensus/crypto/ed25519

  ZIP215 validation rules require:
  1. Using the cofactor-8 verification equation: [8][s]B = [8]R + [8][k]A
  2. Allowing non-canonical point encodings for A and R
  3. Requiring canonical scalar encoding (s < q)
  4. All 196 test vectors should pass with consistent results
  """
  use ExUnit.Case
  alias Util.Crypto

  @test_vectors_file "test_vectors_ed25519.json"

  # Expected behavior for ZIP215-compliant implementation:
  # All 196 vectors should be ACCEPTED because:
  # - They all use s=0 (canonical scalar)
  # - The cofactor-8 equation projects to prime-order subgroup
  # - This eliminates torsion components, making all signatures valid
  # - Non-canonical encodings are permitted by ZIP215

  describe "Ed25519 ZIP215 conformance" do
    test "loads and validates all 196 test vectors from conformance suite" do
      vectors = load_test_vectors()

      assert length(vectors) == 196, "Expected 196 test vectors"

      results =
        Enum.map(vectors, fn vector ->
          %{
            "number" => number,
            "desc" => desc,
            "pk" => pk_hex,
            "r" => r_hex,
            "s" => s_hex,
            "msg" => msg_hex,
            "pk_canonical" => pk_canonical,
            "r_canonical" => r_canonical
          } = vector

          # Decode hex values
          pk = Base.decode16!(pk_hex, case: :lower)
          r = Base.decode16!(r_hex, case: :lower)
          s = Base.decode16!(s_hex, case: :lower)
          msg = Base.decode16!(msg_hex, case: :lower)

          # Signature is R || s (64 bytes total)
          signature = r <> s

          # Test signature verification
          result = Crypto.valid_signature?(signature, msg, pk)

          %{
            number: number,
            desc: desc,
            pk_canonical: pk_canonical,
            r_canonical: r_canonical,
            valid: result
          }
        end)

      # Analyze results
      passed = Enum.count(results, & &1.valid)
      failed = Enum.count(results, &(not &1.valid))

      # Check for any failures
      failures = Enum.filter(results, &(not &1.valid))

      if failed > 0 do
        IO.puts("\n❌ Ed25519 Conformance Test FAILED")
        IO.puts("Total vectors: #{length(results)}")
        IO.puts("Passed: #{passed}")
        IO.puts("Failed: #{failed}")
        IO.puts("\nFailed vectors:")

        Enum.each(failures, fn f ->
          IO.puts("  ##{f.number}: #{f.desc}")
          IO.puts("    pk_canonical: #{f.pk_canonical}, r_canonical: #{f.r_canonical}")
        end)

        # Analyze failure patterns
        analyze_failures(failures)

        flunk("""
        Ed25519 implementation is NOT ZIP215 compliant.
        #{failed}/196 vectors failed.

        This indicates your implementation is likely:
        1. Rejecting non-canonical point encodings (violates ZIP215)
        2. Using the unbatched verification equation instead of cofactor-8
        3. Not properly handling torsion components

        See: https://hdevalence.ca/blog/2020-10-04-its-25519am/
        """)
      end
    end

    test "verify current implementation behavior" do
      # Test with a known canonical signature to see baseline behavior
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      message = "test message"
      signature = Crypto.sign(message, priv)

      assert Crypto.valid_signature?(signature, message, pub),
             "Basic Ed25519 signature verification should work"
    end

    test "test with small-order point (canonical)" do
      # Small order point: (0, 1) - the identity element
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

  # Helper functions

  defp load_test_vectors do
    Path.join([File.cwd!(), "test", @test_vectors_file])
    |> File.read!()
    |> Jason.decode!()
  end

  defp analyze_failures(failures) do
    IO.puts("\n📊 Failure Analysis:")

    # Group by canonicality
    non_canonical_pk = Enum.count(failures, &(not &1.pk_canonical))
    non_canonical_r = Enum.count(failures, &(not &1.r_canonical))
    both_canonical = Enum.count(failures, &(&1.pk_canonical and &1.r_canonical))

    IO.puts("  Failures with non-canonical pk: #{non_canonical_pk}")
    IO.puts("  Failures with non-canonical r: #{non_canonical_r}")
    IO.puts("  Failures with both canonical: #{both_canonical}")

    cond do
      non_canonical_pk > 0 or non_canonical_r > 0 ->
        IO.puts("""

        ⚠️  Your implementation rejects non-canonical point encodings.
        This indicates you're using RFC8032-style validation instead of ZIP215.

        ZIP215 explicitly allows non-canonical encodings to ensure:
        - Batch verification compatibility
        - Consistent consensus across implementations
        - Backwards compatibility with existing signatures
        """)

      both_canonical > 0 ->
        IO.puts("""

        ⚠️  Your implementation rejects even canonical encodings.
        This might indicate:
        - Using unbatched verification equation
        - Torsion component handling issues
        - Small-order point rejection
        """)

      true ->
        IO.puts("\n✓ No pattern detected")
    end
  end
end
