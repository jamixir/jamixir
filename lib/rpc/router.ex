defmodule Jamixir.RPC.Router do
  @moduledoc """
  Router for RPC endpoints.
  """

  use Plug.Router
  alias Jamixir.RPC.{HTTPHandler, WebSocketHandler}

  plug(:match)
  plug(:dispatch)

  forward("/rpc", to: HTTPHandler)

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(WebSocketHandler, %{}, timeout: 60_000)
    |> halt()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
