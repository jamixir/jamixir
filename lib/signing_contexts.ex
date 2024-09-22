defmodule SigningContexts do
  @moduledoc """
  Defines signing contexts used throughout the system for various cryptographic operations.
  """

  # Formula (129) v0.3.4
  @doc "XA - Ed25519 Availability assurances context."
  def jam_available, do: "$jam_available"

  # Formula (210) v0.3.4
  @doc "XB - BLS Accumulate-result-root-mmr commitment context."
  def jam_beefy, do: "$jam_beefy"

  # Formula (63) v0.3.4
  @doc "XE - On-chain entropy generation context."
  def jam_entropy, do: "$jam_entropy"

  # Formula (64) v0.3.4
  @doc "XF - Bandersnatch Fallback block seal context."
  def jam_fallback_seal, do: "$jam_fallback_seal"

  # Formula (142) v0.3.4
  @doc "XG - Ed25519 Guarantee statements context."
  def jam_guarantee, do: "$jam_guarantee"

  # Formula (199) v0.3.4
  @doc "XI - Ed25519 Audit announcement statements context."
  def jam_announce, do: "$jam_announce"

  # Formula (65) v0.3.4
  @doc "XT - Bandersnatch RingVRF Ticket generation and regular block seal context."
  def jam_ticket_seal, do: "$jam_ticket_seal"

  # Formula (193) v0.3.4
  @doc "XU - Bandersnatch Audit selection entropy context."
  def jam_audit, do: "$jam_audit"

  # Formula (100) v0.3.4
  @doc "X⊺ - Ed25519 Judgements for valid work-reports context."
  def jam_valid, do: "$jam_valid"

  # Formula (100) v0.3.4
  @doc "X - Ed25519 Judgements for invalid work-reports context."
  def jam_invalid, do: "$jam_invalid"
end
