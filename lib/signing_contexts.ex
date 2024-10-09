defmodule SigningContexts do
  @moduledoc """
  Defines signing contexts used throughout the system for various cryptographic operations.
  """

  # Formula (128) v0.4.1
  @doc "XA - Ed25519 Availability assurances context."
  def jam_available, do: "jam_available"

  # Formula (226) v0.4.1
  @doc "XB - BLS Accumulate-result-root-mmr commitment context."
  def jam_beefy, do: "jam_beefy"

  # Formula (63) v0.4.1
  @doc "XE - On-chain entropy generation context."
  def jam_entropy, do: "jam_entropy"

  # Formula (64) v0.4.1
  @doc "XF - Bandersnatch Fallback block seal context."
  def jam_fallback_seal, do: "jam_fallback_seal"

  # Formula (141) v0.4.1
  @doc "XG - Ed25519 Guarantee statements context."
  def jam_guarantee, do: "jam_guarantee"

  # Formula (215) v0.4.1
  @doc "XI - Ed25519 Audit announcement statements context."
  def jam_announce, do: "jam_announce"

  # Formula (65) v0.4.1
  @doc "XT - Bandersnatch RingVRF Ticket generation and regular block seal context."
  def jam_ticket_seal, do: "jam_ticket_seal"

  # Formula (208) v0.4.1
  @doc "XU - Bandersnatch Audit selection entropy context."
  def jam_audit, do: "jam_audit"

  # Formula (100) v0.4.1
  @doc "X⊺ - Ed25519 Judgements for valid work-reports context."
  def jam_valid, do: "jam_valid"

  # Formula (100) v0.4.1
  @doc "X - Ed25519 Judgements for invalid work-reports context."
  def jam_invalid, do: "jam_invalid"
end
