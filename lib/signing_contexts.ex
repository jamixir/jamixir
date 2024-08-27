defmodule SigningContexts do
  @moduledoc """
  Defines signing contexts used throughout the system for various cryptographic operations.
  """

  # Ed25519 Availability assurances
  @jam_available "$jam_available"
  # BLS Accumulate-result-root-mmr commitment
  @jam_beefy "$jam_beefy"
  # On-chain entropy generation
  @jam_entropy "$jam_entropy"
  # Bandersnatch Fallback block seal
  @jam_fallback_seal "$jam_fallback_seal"
  # Ed25519 Guarantee statements
  @jam_guarantee "$jam_guarantee"
  # Ed25519 Audit announcement statements
  @jam_announce "$jam_announce"
  # Bandersnatch RingVRF Ticket generation and regular block seal
  @jam_ticket_seal "$jam_ticket_seal"
  # Bandersnatch Audit selection entropy
  @jam_audit "$jam_audit"
  # Ed25519 Judgements for valid work-reports
  @jam_valid "$jam_valid"
  # Ed25519 Judgements for invalid work-reports
  @jam_invalid "$jam_invalid"

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
