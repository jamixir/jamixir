defmodule System.HeaderSeal do
  alias Block.Header
  alias System.State.EntropyPool
  require Logger

  @callback do_validate_header_seals(
              header :: any(),
              curr_validators_ :: any(),
              epoch_slot_sealers_ :: any(),
              entropy_pool :: %EntropyPool{}
            ) ::
              {:ok, %{vrf_signature_output: binary(), block_seal_output: binary()}}
              | {:error, any()}

  def validate_header_seals(
        header,
        curr_validators_,
        epoch_slot_sealers_,
        %EntropyPool{} = entropy_pool
      ) do
    module = Application.get_env(:jamixir, :header_seal, __MODULE__)

    module.do_validate_header_seals(header, curr_validators_, epoch_slot_sealers_, entropy_pool)
  end

  # Formula (6.15) v0.6.0
  # Formula (6.16) v0.6.0
  # Formula (6.17) v0.6.0
  def seal_header(
        %Header{timeslot: ts} = header,
        epoch_slot_sealers,
        %EntropyPool{} = entropy_pool,
        {keypair, _}
      ) do
    # associated with formula (6.15, 6.16) v0.6.0
    # let i = γs′ [Ht ]↺
    expected_slot_sealer =
      Enum.at(epoch_slot_sealers, rem(ts, length(epoch_slot_sealers)))

    seal_context = construct_seal_context(expected_slot_sealer, entropy_pool)
    block_seal_output = RingVrf.ietf_vrf_output(keypair, seal_context)

    # Formula (6.17) v0.6.0
    {vrf_signature, _} =
      RingVrf.ietf_vrf_sign(keypair, SigningContexts.jam_entropy() <> block_seal_output, <<>>)

    header = put_in(header.vrf_signature, vrf_signature)

    {block_seal, _} =
      RingVrf.ietf_vrf_sign(keypair, seal_context, Header.unsigned_encode(header))

    put_in(header.block_seal, block_seal)
  end

  # Formula (6.15) v0.6.0
  # Formula (6.16) v0.6.0
  def do_validate_header_seals(
        header,
        curr_validators_,
        epoch_slot_sealers_,
        %EntropyPool{} = entropy_pool
      ) do
    bandersnatch_public_keys = for v <- curr_validators_, do: v.bandersnatch
    # let i = γs′ [Ht ]↺
    expected_slot_sealer =
      epoch_slot_sealers_ |> Enum.at(rem(header.timeslot, length(epoch_slot_sealers_)))

    # verify that the block seal is a valid signature
    with {:ok, block_seal_output} <-
           RingVrf.ietf_vrf_verify(
             Enum.at(bandersnatch_public_keys, header.block_author_key_index),
             construct_seal_context(expected_slot_sealer, entropy_pool),
             Header.unsigned_encode(header),
             header.block_seal
           ),
         # calulate the output ourselves and compare it to the block seal's output
         :ok <-
           verify_sealer_match(
             expected_slot_sealer,
             block_seal_output,
             header.block_author_key_index,
             curr_validators_
           ),
         # verify that the vrf signature is a valid signature
         # Formula (6.17) v0.6.0
         {:ok, vrf_signature_output} <-
           RingVrf.ietf_vrf_verify(
             Enum.at(bandersnatch_public_keys, header.block_author_key_index),
             SigningContexts.jam_entropy() <> block_seal_output,
             <<>>,
             header.vrf_signature
           ) do
      {:ok, %{block_seal_output: block_seal_output, vrf_signature_output: vrf_signature_output}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_sealer_match(
         <<_::binary>> = correct_slot_sealer,
         _block_seal_output,
         block_author_key_index,
         curr_validators_
       ) do
    case Enum.at(curr_validators_, block_author_key_index) do
      %{bandersnatch: ^correct_slot_sealer} -> :ok
      _ -> {:error, :ticket_id_mismatch}
    end
  end

  defp verify_sealer_match(%{id: block_seal_output}, block_seal_output, _, _), do: :ok
  defp verify_sealer_match(_, _, _, _), do: {:error, :ticket_id_mismatch}

  def construct_seal_context(<<_::binary>>, %EntropyPool{n3: n3}) do
    SigningContexts.jam_fallback_seal() <> n3
  end

  def construct_seal_context(%{attempt: i}, %EntropyPool{n3: n3}) do
    SigningContexts.jam_ticket_seal() <> n3 <> <<i::8>>
  end
end
