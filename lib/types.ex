defmodule Types do
  @moduledoc """
  A module for defining common types.
  """

  @type hash :: <<_::256>>
  @type ed25519_key :: <<_::256>>
  @type bandersnatch_key :: <<_::256>>
  # 144 bytes
  @type bls_key :: <<_::1152>>
  @type ed25519_signature :: <<_::512>>
  @type validator_index :: non_neg_integer()
  @type epoch_index :: non_neg_integer()
  @type decision :: boolean()
  # 144 bytes YR ⊂ Y144
  @type bandersnatch_ring_root :: <<_::1152>>
  @type max_age_timeslot_lookup_anchor :: non_neg_integer() # L
  @type max_validators :: <<_::10>>

  @typedoc """
  Fm∈Yk∈HB ⟨x ∈ Y⟩ ⊂ Y96
   valid singly-contextualized signatures of utilizing the se-
   cret counterpart to the public(Bandersnatch) key k, some context x and
   message m
  """
  @type bandersnatch_signature :: <<_::768>>

  @typedoc """
  F̄m∈Yr∈YR ⟨x ∈ Y⟩ ⊂ Y784 is the set of valid Ban-
  dersnatch Ringvrf deterministic singly-contextualized
  proofs of knowledge of a secret within some set of secrets
  identified by some root in the set of valid roots YR ⊂ Y144 .
  """
  @type bandersnatch_ringVRF_proof_of_knowledge :: <<_::6272>>
end
