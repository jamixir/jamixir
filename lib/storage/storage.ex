defmodule Storage do
  alias Util.Merklization
  alias Block.Header
  alias System.State
  alias Util.Hash
  use Codec.Encoder

  @state_key "state"
  @state_root_key "state_root"
  @latest_timeslot "latest_timeslot"

  def start_link do
    case KVStorage.start_link() do
      {:ok, pid} ->
        # Initialize with zero header
        zero_hash = Hash.zero()
        KVStorage.put(zero_hash, nil)
        KVStorage.put("t:0", nil)
        KVStorage.put(:latest_timeslot, 0)
        {:ok, pid}

      error ->
        error
    end
  end

  def put(%Header{} = header) do
    encoded_header = Encodable.encode(header)
    hash = Hash.default(encoded_header)

    KVStorage.put(%{
      hash => encoded_header,
      "t:#{header.timeslot}" => encoded_header,
      @latest_timeslot => header.timeslot
    })

    {:ok, hash}
  end

  def put(headers) when is_list(headers), do: put_headers(headers)

  def put(%State{} = state) do
    state_root = Merklization.merkelize_state(State.serialize(state))

    KVStorage.put(%{
      @state_key => state,
      @state_root_key => state_root
    })

    :ok
  end

  def put(object) when is_struct(object) do
    case encodable?(object) do
      true -> KVStorage.put(Encodable.encode(object))
      false -> raise "Struct does not implement Encodable protocol"
    end
  end

  def put(blob) when is_binary(blob), do: KVStorage.put(blob)

  def put(items) when is_list(items) do
    # First convert items to {key, value} pairs, stopping if we hit an error
    case Enum.reduce_while(items, [], fn item, acc ->
           case prepare_entry(item) do
             {:ok, entry} -> {:cont, [entry | acc]}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      {:error, reason} ->
        {:error, reason}

      entries ->
        KVStorage.put(entries)
    end
  end

  defp prepare_entry({key, value}), do: {:ok, {key, value}}

  defp prepare_entry(blob) when is_binary(blob) do
    {:ok, {h(blob), blob}}
  end

  defp prepare_entry(struct) when is_struct(struct) do
    if Encodable.impl_for(struct) do
      blob = Encodable.encode(struct)
      {:ok, {h(blob), blob}}
    else
      {:error, "Struct #{struct.__struct__} does not implement Encodable protocol"}
    end
  end

  def get(hash), do: KVStorage.get(hash)

  def get(hash, module) do
    case KVStorage.get(hash) do
      nil ->
        nil

      blob ->
        {h, _rest} = module.decode(blob)
        h
    end
  end

  def remove(key), do: KVStorage.remove(key)
  def remove_all, do: KVStorage.remove_all()

  def get_latest_header do
    case KVStorage.get(@latest_timeslot) do
      nil ->
        nil

      slot ->
        case KVStorage.get("t:#{slot}", Header) do
          nil -> nil
          header -> {slot, header}
        end
    end
  end

  def get_state, do: KVStorage.get(@state_key)
  def get_state_root, do: KVStorage.get(@state_root_key)

  # Private Functions

  defp encodable?(data), do: not is_nil(Encodable.impl_for(data))

  @spec put_headers(list(Header.t())) :: {:ok, list(String.t())}
  defp put_headers(headers) do
    if Enum.all?(headers, &is_struct(&1, Header)) do
      # find the latest timeslot
      latest_timeslot = Enum.max_by(headers, & &1.timeslot, fn -> 0 end).timeslot

      map =
        Enum.reduce(headers, %{}, fn header, acc ->
          blob = Encodable.encode(header)
          acc
          |> Map.put(h(blob), blob)
          |> Map.put("t:#{header.timeslot}", blob)
          |> Map.put(@latest_timeslot, latest_timeslot)
        end)

      KVStorage.put(map)
    else
      {:error, "All items must be Header structs"}
    end
  end
end
