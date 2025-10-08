defmodule Jamixir.Repo do
  use Ecto.Repo,
    otp_app: :jamixir,
    adapter: Ecto.Adapters.SQLite3

  def init(_type, config) do
    {:ok, config}
  end
end
