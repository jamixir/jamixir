defmodule SigningContexts do
  @moduledoc """
  Defines signing contexts used throughout the system for various cryptographic operations.
  """

  # Formula (129) v0.3.4
  @doc "Ed25519 Availability assurances context."
  def jam_available, do: "$jam_available"

  # Formula (210) v0.3.4
  @doc "BLS Accumulate-result-root-mmr commitment context."
  def jam_beefy, do: "$jam_beefy"

  # Formula (63) v0.3.4
  @doc "On-chain entropy generation context."
  def jam_entropy, do: "$jam_entropy"

  # Formula (64) v0.3.4
  @doc "Bandersnatch Fallback block seal context."
  def jam_fallback_seal, do: "$jam_fallback_seal"

  # Ed25519 Guarantee statements
  # Formula (142) v0.3.4
  @doc "Ed25519 Guarantee statements context."
  def jam_guarantee, do: "$jam_guarantee"

  # Ed25519 Audit announcement statements
  # Formula (199) v0.3.4
  @doc "Ed25519 Audit announcement statements context."
  def jam_announce, do: "$jam_announce"

  # Formula (65) v0.3.4
  @doc "Bandersnatch RingVRF Ticket generation and regular block seal context."
  def jam_ticket_seal, do: "$jam_ticket_seal"

  # Bandersnatch Audit selection entropy
  # Formula (193) v0.3.4
  @doc "Bandersnatch Audit selection entropy context."
  def jam_audit, do: "$jam_audit"

  # Ed25519 Judgements for valid work-reports
  # Formula (100) v0.3.4
  @doc "Ed25519 Judgements for valid work-reports context."
  def jam_valid, do: "$jam_valid"

  # Ed25519 Judgements for invalid work-reports
  # Formula (100) v0.3.4
  @doc "Ed25519 Judgements for invalid work-reports context."
  def jam_invalid, do: "$jam_invalid"
end
