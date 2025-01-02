defmodule Storage do
  alias Util.Merklization
  alias Util.Hash
  alias Block.Header
  alias System.State

  @table_name JamObjects
  @state_key "state"
  @state_root_key "state_root"

  def start_link do
    case init_mnesia() do
      :ok ->
        # Initialize with zero header
        zero_hash = Hash.zero()
        :mnesia.transaction(fn ->
          :mnesia.write({@table_name, zero_hash, nil})
          :mnesia.write({@table_name, "t:0", nil})
          :mnesia.write({@table_name, :latest_timeslot, 0})
        end)
        {:ok, self()}  # Return format that matches OTP expectations
      error ->
        error
    end
  end

  def put(object) when is_struct(object), do: put_direct(Encodable.encode(object))
  def put(blob) when is_binary(blob), do: put_direct(blob)

  def put(list) when is_list(list) do
    Enum.map(list, fn
      blob when is_binary(blob) -> put_direct(blob)
      struct when is_struct(struct) -> put_direct(Encodable.encode(struct))
    end)
  end

  def get(hash), do: get_direct(hash)

  def get(hash, module) do
    case get_direct(hash) do
      nil ->
        nil

      blob ->
        {h, _rest} = module.decode(blob)
        h
    end
  end

  def delete(hash) do
    :mnesia.transaction(fn -> :mnesia.delete({@table_name, hash}) end)
  end

  def put_header(%Header{} = header) do
    encoded_header = Encodable.encode(header)
    hash = Hash.default(encoded_header)

    :mnesia.transaction(fn ->
      :mnesia.write({@table_name, hash, encoded_header})
      :mnesia.write({@table_name, "t:#{header.timeslot}", encoded_header})
      :mnesia.write({@table_name, :latest_timeslot, header.timeslot})
    end)
  end

  def get_header(hash) do
    case get_direct(hash) do
      nil ->
        nil

      blob ->
        {h, _} = Block.Header.decode(blob)
        h
    end
  end

  def header_exists?(hash), do: get_direct(hash) != nil

  def get_latest_header do
    case get_direct(:latest_timeslot) do
      nil ->
        nil

      slot ->
        case get("t:#{slot}", Header) do
          nil -> nil
          header -> {slot, header}
        end
    end
  end

  def put_state(%State{} = state) do
    state_root = Merklization.merkelize_state(State.serialize(state))

    :mnesia.transaction(fn ->
      :mnesia.write({@table_name, @state_key, state})
      :mnesia.write({@table_name, @state_root_key, state_root})
    end)
  end

  def get_state, do: get_direct(@state_key)
  def get_state_root, do: get_direct(@state_root_key)

  # Private Functions
  defp init_mnesia do
    :mnesia.create_schema([node()])
    :mnesia.start()

    case :mnesia.create_table(@table_name,
           attributes: [:hash, :blob],
           record_name: @table_name
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table_name}} -> :ok
      error -> {:error, error}
    end
  end

  defp put_direct(blob) when is_binary(blob) do
    hash = Hash.default(blob)
    case :mnesia.transaction(fn -> :mnesia.write({@table_name, hash, blob}) end) do
      {:atomic, :ok} -> :ok
      error -> {:error, error}
    end
  end

  defp get_direct(key) do
    case :mnesia.transaction(fn -> :mnesia.read({@table_name, key}) end) do
      {:atomic, [{@table_name, _hash, blob}]} -> blob
      {:atomic, []} -> nil
      {:aborted, {:no_exists, _}} -> nil
      _ -> nil
    end
  end
end
