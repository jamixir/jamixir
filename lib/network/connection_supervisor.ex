defmodule Network.ConnectionSupervisor do
  @moduledoc """
  Supervises Connection processes and acts as the connection registry.
  Prevents duplicate connections and provides connection lookup.
  """

  use DynamicSupervisor
  alias Util.Logger, as: Log

  def start_link(args \\ []) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_outbound_connection(ip, port) do
    ip_string = format_ip_address(ip)

    if has_connection?(ip_string, port) do
      Log.connection(
        :debug,
        "🔄 Connection already exists, returning existing",
        "#{ip_string}:#{port}"
      )

      case get_connection(ip_string, port) do
        {:ok, pid} -> {:ok, pid}
        error -> error
      end
    else
      normalized_ip = if is_list(ip), do: ip, else: to_charlist(ip)

      spec = %{
        id: {:outbound_connection, ip_string, port, System.unique_integer()},
        start:
          {Network.Connection, :start_link,
           [%{init_mode: :initiator, ip: normalized_ip, port: port}]},
        restart: :transient,
        type: :worker
      }

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Log.connection(:debug, "✅ Started outbound connection", "#{ip_string}:#{port}")
          {:ok, pid}

        error ->
          Log.connection(
            :warning,
            "❌ Failed to start outbound connection: #{inspect(error)}",
            "#{ip_string}:#{port}"
          )

          error
      end
    end
  end

  def start_inbound_connection(conn, remote_address, remote_port, local_port) do
    if has_connection?(remote_address, remote_port) do
      Log.connection(
        :debug,
        "🚫 Connection already exists, rejecting duplicate",
        "#{remote_address}:#{remote_port}"
      )

      :quicer.close_connection(conn)
      {:error, :already_exists}
    else
      spec = %{
        id: {:inbound_connection, remote_address, remote_port, System.unique_integer()},
        start:
          {Network.Connection, :start_link,
           [
             %{
               connection: conn,
               remote_address: remote_address,
               remote_port: remote_port,
               local_port: local_port
             }
           ]},
        restart: :transient,
        type: :worker
      }

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Log.connection(
            :debug,
            "✅ Started inbound connection",
            "#{remote_address}:#{remote_port}"
          )

          {:ok, pid}

        error ->
          Log.connection(
            :warning,
            "❌ Failed to start inbound connection: #{inspect(error)}",
            "#{remote_address}:#{remote_port}"
          )

          :quicer.close_connection(conn)
          error
      end
    end
  end

  # Kill a connection process - used when QUIC connection is dead but process is alive
  def kill_connection(remote_address, remote_port) do
    case get_connection(remote_address, remote_port) do
      {:ok, pid} ->
        Log.connection(
          :debug,
          "🔪 Killing dead connection process",
          "#{remote_address}:#{remote_port}"
        )

        DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok

      {:error, :not_found} ->
        Log.connection(:debug, "🔍 No process found", "#{remote_address}:#{remote_port}")
        :ok
    end
  end

  # Connection registry functions (using supervised children)
  def has_connection?(remote_address, remote_port) do
    get_connection(remote_address, remote_port) != {:error, :not_found}
  end

  def get_connection(remote_address, remote_port) do
    children = DynamicSupervisor.which_children(__MODULE__)

    Enum.find_value(children, {:error, :not_found}, fn
      {_id, pid, :worker, [Network.Connection]} when is_pid(pid) ->
        # Ask the connection process for its remote address
        try do
          case GenServer.call(pid, :get_remote_address, 1000) do
            {^remote_address, ^remote_port} -> {:ok, pid}
            _ -> nil
          end
        catch
          :exit, _ -> nil
        end

      _ ->
        nil
    end)
  end

  def get_all_connections do
    children = DynamicSupervisor.which_children(__MODULE__)

    children
    |> Enum.filter(fn {_id, pid, :worker, [Network.Connection]} -> is_pid(pid) end)
    |> Enum.map(fn {_id, pid, :worker, [Network.Connection]} -> pid end)
    |> Enum.map(fn pid ->
      try do
        case GenServer.call(pid, :get_remote_address, 1000) do
          {remote_address, remote_port} -> {"#{remote_address}:#{remote_port}", pid}
          _ -> nil
        end
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Map.new()
  end


  # Helper function to format IP addresses consistently
  defp format_ip_address({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip_address(ip) when is_binary(ip), do: ip
  defp format_ip_address(ip) when is_list(ip), do: List.to_string(ip)
  defp format_ip_address(ip), do: inspect(ip)
end
