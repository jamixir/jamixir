defmodule SigningContexts do
  @moduledoc """
  Defines signing contexts used throughout the system for various cryptographic operations.
  """

  # Formula (63) v0.3.4
  @jam_entropy "$jam_entropy"
  # Formula (64) v0.3.4
  @jam_fallback_seal "$jam_fallback_seal"
  # Formula (65) v0.3.4
  @jam_ticket_seal "$jam_ticket_seal"
  # Ed25519 Availability assurances
  # Formula (129) v0.3.4
  @jam_available "$jam_available"
  # Ed25519 Judgements for valid work-reports
  # Formula (100) v0.3.4
  @jam_valid "$jam_valid"
  # Ed25519 Judgements for invalid work-reports
  # Formula (100) v0.3.4
  @jam_invalid "$jam_invalid"
  # Ed25519 Guarantee statements
  # Formula (142) v0.3.4
  @jam_guarantee "$jam_guarantee"
  # Bandersnatch Audit selection entropy
  # Formula (193) v0.3.4
  @jam_audit "$jam_audit"
  # Ed25519 Audit announcement statements
  # Formula (199) v0.3.4
  @jam_announce "$jam_announce"
  # BLS Accumulate-result-root-mmr commitment
  # Formula (210) v0.3.4
  @jam_beefy "$jam_beefy"

  @doc "Ed25519 Availability assurances context."
  def jam_available, do: @jam_available

  @doc "BLS Accumulate-result-root-mmr commitment context."
  def jam_beefy, do: @jam_beefy

  @doc "On-chain entropy generation context."
  def jam_entropy, do: @jam_entropy

  @doc "Bandersnatch Fallback block seal context."
  def jam_fallback_seal, do: @jam_fallback_seal

  @doc "Ed25519 Guarantee statements context."
  def jam_guarantee, do: @jam_guarantee

  @doc "Ed25519 Audit announcement statements context."
  def jam_announce, do: @jam_announce

  @doc "Bandersnatch RingVRF Ticket generation and regular block seal context."
  def jam_ticket_seal, do: @jam_ticket_seal

  @doc "Bandersnatch Audit selection entropy context."
  def jam_audit, do: @jam_audit

  @doc "Ed25519 Judgements for valid work-reports context."
  def jam_valid, do: @jam_valid

  @doc "Ed25519 Judgements for invalid work-reports context."
  def jam_invalid, do: @jam_invalid
end
