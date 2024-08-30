defmodule Util.Safrole do
  # Function to find the correct slot sealer based on the timeslot
  # used to verify the signatures in the header (importer)
  # Formula (60),(61) v0.3.4
  def get_correct_slot_sealer(posterior_epoch_slot_sealers, timeslot) do
    Enum.at(posterior_epoch_slot_sealers, rem(timeslot, length(posterior_epoch_slot_sealers)))
  end

  # Function to find the index of a validator's public key in a list of validators
  # used to sign blocks (author)
  def find_author_index(validators, public_key) do
    validators
    |> Enum.find_index(fn validator -> validator.bandersnatch == public_key end)
  end

  # Function to determine if a sealer is a fallback sealer
  # used to determine the context data when sign/verify an header
  def is_fallback_sealer?(correct_slot_sealer) do
    case correct_slot_sealer do
      <<_::binary>> -> true
      %{} -> false
      _ -> raise "Unknown sealer type"
    end
  end

  # Function to construct signing context based on the correct slot sealer and entropy pool history
  def construct_sign_context(correct_slot_sealer, entropy_pool_history) do
    if is_fallback_sealer?(correct_slot_sealer) do
      SigningContexts.jam_fallback_seal() <> Enum.at(entropy_pool_history, 2)
    else
      SigningContexts.jam_ticket_seal() <>
        Enum.at(entropy_pool_history, 2) <>
        <<Map.get(correct_slot_sealer, :entry_index)::8>>
    end
  end
end
