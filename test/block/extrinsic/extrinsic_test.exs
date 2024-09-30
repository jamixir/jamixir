defmodule Block.ExtrinsicTest do
  use ExUnit.Case

  alias Block.Extrinsic.{Guarantee, Guarantee.WorkReport}
  alias System.State.Validator
  alias Util.Crypto
  alias SigningContexts
  alias Util.Hash

  setup_all do
    keypairs = for _ <- 1..3, do: :crypto.generate_key(:eddsa, :ed25519)
    validators = Enum.map(keypairs, fn {pub, _} -> %Validator{ed25519: pub} end)

    %{
      validators: validators,
      keypairs: keypairs
    }
  end

  defp create_guarantees(keypairs) do
    [
      create_guarantee(1, Enum.take(keypairs, 2)),
      create_guarantee(2, keypairs)
    ]
  end

  defp create_guarantee(core_index, keypairs) do
    work_report = %WorkReport{core_index: core_index}
    message = SigningContexts.jam_guarantee() <> Hash.default(Codec.Encoder.encode(work_report))

    credentials =
      keypairs
      |> Enum.with_index()
      |> Enum.map(fn {{_, priv}, index} -> {index, Crypto.sign(message, priv)} end)

    %Guarantee{
      work_report: work_report,
      timeslot: 100,
      credential: credentials
    }
  end

  describe "guarantees/2" do
    test "returns :ok for valid guarantees with correct signatures", %{validators: validators, keypairs: keypairs} do
      guarantees = create_guarantees(keypairs)
      assert Guarantee.validate(guarantees, validators) == :ok
    end

    test "returns error for guarantees with an incorrect signature", %{validators: validators, keypairs: keypairs} do
      [keypair1, keypair2, keypair3] = keypairs
      guarantees = [
        create_guarantee(1, [keypair1, keypair2]),
        create_guarantee(2, [keypair1, keypair2, keypair3])
        |> Map.update!(:credential, fn creds ->
          List.update_at(creds, 1, fn {idx, _sig} ->
            {idx, <<1::512>>}
          end)
        end)
      ]
      assert Guarantee.validate(guarantees, validators) == {:error, "Invalid signature in one or more guarantees"}
    end

    test "returns error for duplicate core_index in guarantees", %{validators: validators} do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<1::512>>}, {2, <<2::512>>}]
        },
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<3::512>>}, {2, <<4::512>>}]
        }
      ]
      assert Guarantee.validate(guarantees, validators) ==
               {:error, "Duplicate core_index found in guarantees"}
    end

    test "returns error for invalid credential length", %{validators: validators} do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<1::512>>}]
        }
      ]
      assert Guarantee.validate(guarantees, validators) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "returns error for credentials not ordered by validator_index", %{validators: validators} do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{2, <<1::512>>}, {1, <<2::512>>}]
        }
      ]
      assert Guarantee.validate(guarantees, validators) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "returns error for duplicate validator_index in credentials", %{validators: validators} do
      guarantees = [
        %Guarantee{
          work_report: %WorkReport{core_index: 1},
          timeslot: 100,
          credential: [{1, <<1::512>>}, {1, <<2::512>>}]
        }
      ]
      assert Guarantee.validate(guarantees, validators) ==
               {:error, "Invalid credentials in one or more guarantees"}
    end

    test "handles empty list of guarantees", %{validators: validators} do
      assert Guarantee.validate([], validators) == :ok
    end

    test "validates a single guarantee correctly", %{validators: validators, keypairs: keypairs} do
      guarantee = create_guarantee(1, Enum.take(keypairs, 2))
      assert Guarantee.validate([guarantee], validators) == :ok
    end
  end
end
