defmodule Types do
  @moduledoc """
  A module for defining common types.
  """
  import TypeMacro

  # Macro to define a binary type with a given size name (defined in Sizes module)
  def_bin_type(:hash, :hash)
  def_bin_type(:ed25519_key, :hash)
  def_bin_type(:bandersnatch_key, :hash)
  def_bin_type(:ed25519_signature, :signature)
  def_bin_type(:bitfield, :bitfield)

  @typedoc """
  Fm∈Yk∈HB ⟨x ∈ Y⟩ ⊂ Y96
   valid singly-contextualized signatures of utilizing the se-
   cret counterpart to the public(Bandersnatch) key k, some context x and
   message m
  """
  def_bin_type(:bandersnatch_signature, :bandersnatch_signature)

  @typedoc """
  F̄m∈Yr∈YR ⟨x ∈ Y⟩ ⊂ Y784 is the set of valid Ban-
  dersnatch Ringvrf deterministic singly-contextualized
  proofs of knowledge of a secret within some set of secrets
  identified by some root in the set of valid roots YR ⊂ Y144 .
  """
  def_bin_type(:bandersnatch_ringVRF_proof_of_knowledge, :bandersnatch_proof)

  # @hash_size

  # Formula (14.1) v0.6.6 - G ≡ YWG
  # (4104 * 8)
  def_bin_type(:export_segment, :export_segment)

  # 144 bytes
  @type bls_key :: <<_::1152>>
  @type validator_index :: non_neg_integer()
  @type epoch_index :: non_neg_integer()
  # Formula (4.28) v0.7.0 - should be guarded as <= 2^32
  @type timeslot :: non_neg_integer()
  # Formula (4.21) v0.7.0 - ℕ_B - should be guarded as <= 2^64
  @type balance :: non_neg_integer()
  # Formula (4.23) v0.7.0 - ℕ_G - shoud be a 64-bit integer <= 2^64
  @type gas :: non_neg_integer()
  # Formula (4.23) v0.7.0 - ZG - shoud be a 64-bit signed (-2^63..2^63)
  @type gas_result :: integer()
  # Formula (4.23) v0.7.0 - ℕ_R - shoud be a 64-bit integer <= 2^64
  @type register :: non_neg_integer()
  @type service_index :: non_neg_integer()
  @type memory_access :: :write | :read | nil
  @type vote :: boolean()
  # 144 bytes YR ⊂ Y144
  @type bandersnatch_ring_root :: <<_::1152>>
  # L
  @type max_age_timeslot_lookup_anchor :: non_neg_integer()

  @type segment_ref ::
          hash()
          | {:tagged_hash, hash()}

  # Network IP address types
  @type ipv4_address :: {0..255, 0..255, 0..255, 0..255}
  @type ipv6_address ::
          {0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535, 0..65_535}
  @type ip_address :: ipv4_address() | ipv6_address()
  @type port_number :: 1..65_535

  @spec tagged?(segment_ref()) :: boolean()
  def tagged?(hash) when is_binary(hash), do: false
  def tagged?({:tagged_hash, _}), do: true

  @spec hash(segment_ref()) :: hash()
  def hash(hash) when is_binary(hash), do: hash
  def hash({:tagged_hash, hash}), do: hash
end
