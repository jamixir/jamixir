defmodule Jamixir.RPC.HTTPHandler do
  @moduledoc """
  HTTP handler for JSON-RPC requests.
  """

  use Plug.Router
  alias Jamixir.RPC.Handler

  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  post "/" do
    case conn.body_params do
      %{} = json_rpc_request when json_rpc_request != %{} ->
        response = Handler.handle_request(json_rpc_request)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(response))

      _ ->
        error_response = %{
          jsonrpc: "2.0",
          error: %{code: -32700, message: "Parse error"},
          id: nil
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(error_response))
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
