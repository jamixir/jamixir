defmodule Network.StreamUtils do
  alias Util.Hash

  def format_stream_ref(stream_ref) when is_reference(stream_ref) do
    :erlang.term_to_binary(stream_ref)
    |> Hash.default()
    |> Base.encode16(case: :upper)
    |> String.slice(0, 6)
  end

  def format_stream_ref(other), do: inspect(other)

  @protocol_desc %{
    0 => "block_announce",
    128 => "req_blocks",
    129 => "req_state",
    131 => "ticket_proxy",
    132 => "ticket_validator",
    133 => "work_package",
    134 => "work_bundle",
    135 => "guarantee",
    136 => "work_report",
    137 => "req_wp_shard",
    138 => "req_audit_shard",
    139 => "req_shards",
    140 => "req_shards_just",
    141 => "assurance",
    142 => "announce_preimage",
    143 => "get_preimage",
    144 => "announce_audit",
    145 => "announce_judgement"
  }
  def protocol_description(protocol_id),
    do: Map.get(@protocol_desc, protocol_id, "unknown_#{protocol_id}")
end
