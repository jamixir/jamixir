defmodule System.HeaderSealTest do
  use ExUnit.Case
  import Jamixir.Factory

  alias System.HeaderSeal
  alias Block.Header

  setup do
    %{validators: validators, key_pairs: key_pairs} = validator_and_key_pairs_factory()
    entropy_pool = build(:entropy_pool)
    epoch_slot_sealers = seal_key_ticket_factory(key_pairs, entropy_pool.history)

    {:ok,
     %{
       validators: validators,
       key_pairs: key_pairs,
       epoch_slot_sealers: epoch_slot_sealers,
       entropy_pool: entropy_pool,
       header: build(:header, timeslot: 2, block_author_key_index: 2)
     }}
  end

  describe "Header sealing functionality" do
    test "successfully seals a header with valid inputs", %{
      key_pairs: kp,
      entropy_pool: ep,
      header: h
    } do
      sealed_header =
        HeaderSeal.seal_header(
          h,
          [single_seal_key_ticket_factory(kp, ep.history, 0)],
          ep,
          hd(kp)
        )

      assert byte_size(sealed_header.vrf_signature) == 96
      assert byte_size(sealed_header.block_seal) == 96

      sealed_header =
        HeaderSeal.seal_header(
          h,
          [single_seal_key_ticket_factory(kp, ep.history, 0)],
          ep,
          hd(kp)
        )

      assert byte_size(sealed_header.vrf_signature) == 96
      assert byte_size(sealed_header.block_seal) == 96
    end

    test "successfully seals a header with large timeslot value", %{
      key_pairs: kp,
      entropy_pool: ep
    } do
      sealed_header =
        HeaderSeal.seal_header(
          build(:header, timeslot: 1_000_000),
          [single_seal_key_ticket_factory(kp, ep.history, 0)],
          ep,
          {elem(Enum.at(kp, 0), 0), :crypto.strong_rand_bytes(32)}
        )

      assert byte_size(sealed_header.vrf_signature) == 96
      assert byte_size(sealed_header.block_seal) == 96
    end
  end

  describe "Fallback sealer handling" do
    test "successfully seals a header with a fallback sealer", %{
      key_pairs: kp,
      entropy_pool: ep,
      header: h
    } do
      fallback_sealer = <<1, 2, 3>>

      sealed_header =
        HeaderSeal.seal_header(
          h,
          [fallback_sealer],
          ep,
          hd(kp)
        )

      assert byte_size(sealed_header.vrf_signature) == 96
      assert byte_size(sealed_header.block_seal) == 96
    end

    test "successfully validates a header sealed with a fallback sealer", %{
      key_pairs: kp,
      entropy_pool: ep,
      validators: validators,
      header: h
    } do
      fallback_sealer = Enum.at(validators, h.block_author_key_index).bandersnatch

      sealed_header =
        HeaderSeal.seal_header(
          h,
          [fallback_sealer],
          ep,
          Enum.at(kp, h.block_author_key_index)
        )

      {:ok, _} =
        HeaderSeal.validate_header_seals(
          sealed_header,
          validators,
          [fallback_sealer],
          ep
        )
    end
  end

  describe "Header seal validation" do
    test "successfully validates a correctly sealed header", %{
      key_pairs: kp,
      entropy_pool: ep,
      epoch_slot_sealers: epoch_slot_sealers,
      validators: validators,
      header: h
    } do
      sealed_header = HeaderSeal.seal_header(h, epoch_slot_sealers, ep, Enum.at(kp, h.timeslot))

      assert {:ok, _} =
               HeaderSeal.validate_header_seals(sealed_header, validators, epoch_slot_sealers, ep)
    end

    test "fails validation with an invalid block seal", %{
      key_pairs: kp,
      entropy_pool: ep,
      epoch_slot_sealers: epoch_slot_sealers,
      validators: validators,
      header: h
    } do
      tampered_header = %Header{
        HeaderSeal.seal_header(h, epoch_slot_sealers, ep, hd(kp))
        | block_seal: <<0::256>>
      }

      assert {:error, _} =
               HeaderSeal.validate_header_seals(
                 tampered_header,
                 validators,
                 epoch_slot_sealers,
                 ep
               )
    end

    test "fails validation with an invalid VRF signature", %{
      key_pairs: kp,
      entropy_pool: ep,
      epoch_slot_sealers: epoch_slot_sealers,
      validators: validators,
      header: h
    } do
      tampered_header = %Header{
        HeaderSeal.seal_header(h, epoch_slot_sealers, ep, hd(kp))
        | vrf_signature: <<0::256>>
      }

      assert {:error, _} =
               HeaderSeal.validate_header_seals(
                 tampered_header,
                 validators,
                 epoch_slot_sealers,
                 ep
               )
    end

    test "fails validation when ticket ID does not match", %{
      key_pairs: kp,
      entropy_pool: ep,
      epoch_slot_sealers: epoch_slot_sealers,
      validators: validators,
      header: h
    } do
      h = %{h | timeslot: 0, block_author_key_index: 0}

      sealed_header = HeaderSeal.seal_header(h, epoch_slot_sealers, ep, hd(kp))

      tampered_sealers = [%{hd(epoch_slot_sealers) | id: <<0::256>>}]

      assert {:error, :ticket_id_mismatch} =
               HeaderSeal.validate_header_seals(
                 sealed_header,
                 validators,
                 tampered_sealers,
                 ep
               )
    end
  end
end
