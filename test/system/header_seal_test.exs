defmodule System.HeaderSealTest do
  use ExUnit.Case
  import Jamixir.Factory
  import TestVectorUtil

  alias Block.Header
  alias System.HeaderSeal
  alias System.State.EntropyPool
  alias Util.Hash

  setup do
    RingVrf.init_ring_context()
    %{validators: validators, key_pairs: key_pairs} = validators_and_bandersnatch_keys()
    entropy_pool = build(:entropy_pool)
    epoch_slot_sealers = seal_key_ticket_factory(key_pairs, entropy_pool)

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
          [single_seal_key_ticket_factory(kp, ep, 0)],
          ep,
          hd(kp)
        )

      assert byte_size(sealed_header.vrf_signature) == 96
      assert byte_size(sealed_header.block_seal) == 96

      sealed_header =
        HeaderSeal.seal_header(
          h,
          [single_seal_key_ticket_factory(kp, ep, 0)],
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
          [single_seal_key_ticket_factory(kp, ep, 0)],
          ep,
          {elem(Enum.at(kp, 0), 0), Hash.random()}
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
        HeaderSeal.validate_header_seals(sealed_header, validators, [fallback_sealer], ep)
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
      sealed_header =
        HeaderSeal.seal_header(h, epoch_slot_sealers, ep, Enum.at(kp, h.timeslot))

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
        | block_seal: Hash.zero()
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
        | vrf_signature: Hash.zero()
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

      tampered_sealers = [%{hd(epoch_slot_sealers) | id: Hash.zero()}]

      assert {:error, :ticket_id_mismatch} =
               HeaderSeal.validate_header_seals(sealed_header, validators, tampered_sealers, ep)
    end
  end

  describe "Seal Test vectors" do
    test("fallback", do: for(i <- [0, 1, 2, 4, 5], do: validate(0, i)))
    test("normal", do: for(i <- 0..5, do: validate(1, i)))
  end

  def validate(t, index) do
    filename = "#{t}-#{index}.json"

    {:ok, j} =
      fetch_and_parse_json(filename, "jamixir/test/seals/", "", "", "")
      |> JsonDecoder.from_json()

    json = JsonDecoder.from_json(j)
    {h, _} = Header.decode(json[:header_bytes])
    assert h.block_seal == json[:H_s]
    assert h.vrf_signature == json[:H_v]

    if t == 0 do
      assert json[:c_for_H_s] ==
               System.HeaderSeal.construct_seal_context(json[:bandersnatch_pub], %EntropyPool{
                 n3: json[:eta3]
               })
    else
      assert json[:c_for_H_s] ==
               System.HeaderSeal.construct_seal_context(%{attempt: json[:attempt]}, %EntropyPool{
                 n3: json[:eta3]
               })
    end

    assert {:ok, output} =
             RingVrf.ietf_vrf_verify(
               json[:bandersnatch_pub],
               json[:c_for_H_s],
               Header.unsigned_encode(h),
               h.block_seal
             )

    assert SigningContexts.jam_entropy() <> output == json[:c_for_H_v]

    assert {:ok, _} =
             RingVrf.ietf_vrf_verify(
               json[:bandersnatch_pub],
               json[:c_for_H_v],
               <<>>,
               h.vrf_signature
             )
  end

  def dec(x) do
    Base.decode16!(x, case: :lower)
  end
end
