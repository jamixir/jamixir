defmodule Storage do
  alias Block.Header
  alias Codec.Encoder
  alias Util.Hash

  require Logger
  use SelectiveMock

  @table_name :header_store
  def table_name, do: @table_name

  def start_link do
    init_mnesia()
  end

  def get_parent(%Header{parent_hash: parent_hash, timeslot: timeslot}) do
    case :mnesia.dirty_read(@table_name, {timeslot - 1, parent_hash}) do
      [{@table_name, {parent_timeslot, ^parent_hash}, parent_header}] ->
        if parent_timeslot < timeslot do
          {:ok, parent_header}
        else
          {:error, "Invalid timeslot order"}
        end

      [] ->
        {:error, "Parent header not found"}
    end
  end

  def put(%Header{} = header) do
    hash = Hash.default(Encoder.encode(header))

    case :mnesia.transaction(fn ->
           :mnesia.write({@table_name, {header.timeslot, hash}, header})
           clean_up_old_headers()
         end) do
      {:atomic, _} -> {:ok, hash}
      {:aborted, reason} -> {:error, reason}
    end
  end

  def get_latest do
    case :mnesia.transaction(fn -> :mnesia.last(@table_name) end) do
      {:atomic, :"$end_of_table"} ->
        nil

      {:atomic, key} ->
        key

      {:aborted, reason} ->
        Logger.error("Failed to get latest finalized block header: #{inspect(reason)}")
        nil
    end
  end

  # Private functions

  defp init_mnesia do
    :mnesia.create_schema([node()])
    :mnesia.start()

    case :mnesia.create_table(@table_name,
           attributes: [:composite_key, :header],
           record_name: @table_name,
           type: :ordered_set
         ) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, @table_name}} ->
        :ok

      error ->
        Logger.error("Failed to create Mnesia table: #{inspect(error)}")
        {:error, error}
    end
  end

  defp clean_up_old_headers do
    count = :mnesia.table_info(@table_name, :size)

    if count >= Constants.max_age() do
      case :mnesia.first(@table_name) do
        :"$end_of_table" ->
          Logger.warning("No blocks found to delete")

        key ->
          :mnesia.delete({@table_name, key})
      end
    end
  end

  mockable exists?(hash) do
    case :mnesia.transaction(fn ->
           :mnesia.match_object({@table_name, {:'$1', hash}, :'$2'})
         end) do
      {:atomic, [{@table_name, {_, ^hash}, _}]} -> true
      {:atomic, []} -> false
      {:aborted, reason} ->
        Logger.error("Failed to check hash existence: #{inspect(reason)}")
        false
    end
  end

  def mock(:exists?, _), do: true
end
