defmodule Util.Export do
  alias Base
  alias Codec.JsonEncoder
  alias Util.Time
  import Util.Hex
  require Logger

  def canonical_order(state_map) do
    key_order = [
      :alpha,
      :beta,
      :gamma,
      :delta,
      :eta,
      :iota,
      :kappa,
      :lambda,
      :rho,
      :tau,
      :varphi,
      :chi,
      :psi,
      :pi,
      :theta,
      :xi
    ]

    key_order
    |> Enum.map(fn key -> {key, Map.get(state_map, key)} end)
    |> Jason.OrderedObject.new()
  end

  @doc """
  Export state to JSON files. Can be called with either:
  - output_dir and {epoch, epoch_phase} tuple
  - output_dir and custom filename (without .json extension)

  Examples:
      Export.export(state, "output/dir")
      Export.export(state, "output/dir", {0, 1})
      Export.export(state, "output/dir", "my_custom_state")
  """
  def export(%System.State{} = s, output_dir) do
    export(s, output_dir, {Time.epoch_index(s.timeslot), Time.epoch_phase(s.timeslot)})
  end

  def export(%System.State{} = s, output_dir, %{epoch: e, epoch_phase: ep}) do
    padded_ep = String.pad_leading("#{ep}", 3, "0")
    do_export(s, output_dir, "state_#{e}_#{padded_ep}", "state_trie_#{e}_#{padded_ep}")
  end

  def export(%System.State{} = s, output_dir, {epoch, epoch_phase}) do
    export(s, output_dir, %{epoch: epoch, epoch_phase: epoch_phase})
  end

  def export(%System.State{} = s, output_dir, filename) when is_binary(filename) do
    do_export(s, output_dir, filename, "#{filename}_trie")
  end

  defp do_export(%System.State{} = s, output_dir, state_filename, trie_filename) do
    state_snapshot = JsonEncoder.encode(s) |> canonical_order()
    trie = Codec.State.Trie.serialize_hex(s, prefix: true)
    state_root = b16(Codec.State.Trie.state_root(s))

    keyvals =
      for {key, val} <- trie, do: [key, val, get_key_name(decode16!(key))]

    state_trie = %{
      state_root: state_root,
      keyvals: keyvals
    }

    File.mkdir_p!(output_dir)

    state_path = Path.join(output_dir, "#{state_filename}.json")
    trie_path = Path.join(output_dir, "#{trie_filename}.json")

    File.write!(state_path, Jason.encode!(state_snapshot, pretty: true))
    File.write!(trie_path, Jason.encode!(state_trie, pretty: true))

    %{
      state_snapshot: state_path,
      state_trie: trie_path
    }
  end

  # Helper to determine key name based on the key prefix
  def get_key_name(<<_::8, 0xFF, _::8, 0xFF, _::8, 0xFF, _::8, 0xFF, _::binary>>),
    do: "account_storage"

  def get_key_name(<<_::8, 0xFE, _::8, 0xFF, _::8, 0xFF, _::8, 0xFF, _::binary>>),
    do: "account_preimage_p"

  def get_key_name(<<_::8, 0xFD, _::8, 0xFF, _::8, 0xFF, _::8, 0xFF, _::binary>>),
    do: "account_preimage_l"

  def get_key_name(<<0xFF, _::binary>>), do: "service_account"
  def get_key_name(<<key::8, _::binary>>) when key in 1..15, do: "c#{key}"

  def get_key_name(_), do: "unknown"
end
