defmodule Disputes.CulpritTest do
  use ExUnit.Case

  alias Disputes.Culprit
  alias Types

  test "valid_signature?/1 returns true for valid signature" do
    # Assume `:crypto.generate_key/2` generates a valid key pair
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    work_report_hash = :crypto.hash(:sha256, "work report")
    signature = :crypto.sign(:eddsa, :none, work_report_hash, [private_key, :ed25519])

    culprit = %Culprit{
      work_report_hash: work_report_hash,
      signature: signature,
      validator_key: public_key
    }

    assert Culprit.valid_signature?(culprit)
  end

  test "valid_signature?/1 returns false for invalid signature" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    work_report_hash = :crypto.hash(:sha256, "work report")

    invalid_signature =
      :crypto.sign(:eddsa, :none, work_report_hash, [private_key, :ed25519]) <> "invalid"

    culprit = %Culprit{
      work_report_hash: work_report_hash,
      signature: invalid_signature,
      validator_key: public_key
    }

    refute Culprit.valid_signature?(culprit)
  end

  test "valid_signature?/1 returns false for incorrect work report hash" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    work_report_hash = :crypto.hash(:sha256, "work report")
    wrong_work_report_hash = :crypto.hash(:sha256, "different work report")
    signature = :crypto.sign(:eddsa, :none, work_report_hash, [private_key, :ed25519])

    culprit = %Culprit{
      work_report_hash: wrong_work_report_hash,
      signature: signature,
      validator_key: public_key
    }

    refute Culprit.valid_signature?(culprit)
  end
end
