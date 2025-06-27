defmodule SigningContexts do
  @moduledoc """
  Appendix I.4.5
  """

  # Formula (11.14) v0.6.6
  @doc "XA - Ed25519 Availability assurances context."
  def jam_available, do: "jam_available"

  # Formula (18.2) v0.6.6
  @doc "XB - BLS Accumulate-result-root-mmr commitment context."
  def jam_beefy, do: "jam_beefy"

  # Formula (6.18) v0.7.0
  @doc "XE - On-chain entropy generation context."
  def jam_entropy, do: "jam_entropy"

  # Formula (6.19) v0.7.0
  @doc "XF - Bandersnatch Fallback block seal context."
  def jam_fallback_seal, do: "jam_fallback_seal"

  # Formula (11.27) v0.6.6
  @doc "XG - Ed25519 Guarantee statements context."
  def jam_guarantee, do: "jam_guarantee"

  # Formula (17.11) v0.6.6
  @doc "XI - Ed25519 Audit announcement statements context."
  def jam_announce, do: "jam_announce"

  # Formula (6.20) v0.7.0
  @doc "XT - Bandersnatch RingVRF Ticket generation and regular block seal context."
  def jam_ticket_seal, do: "jam_ticket_seal"

  # Formula (17.4) v0.6.6
  @doc "XU - Bandersnatch Audit selection entropy context."
  def jam_audit, do: "jam_audit"

  # Formula (10.4) v0.6.6
  @doc "X⊺ - Ed25519 Judgements for valid work-reports context."
  def jam_valid, do: "jam_valid"

  # Formula (10.4) v0.6.6
  @doc "X - Ed25519 Judgements for invalid work-reports context."
  def jam_invalid, do: "jam_invalid"
end
