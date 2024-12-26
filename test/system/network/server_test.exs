defmodule System.Network.ServerTest do
  use ExUnit.Case

  alias System.Network.CertUtils
  alias System.Network.Server

  setup_all do
    opts =
      Server.fixed_opts() ++
        [
          certfile: ~c"./test/system/network/alice_cert.pem",
          keyfile: ~c"./test/system/network/alice_key.pem"
        ]

    {:ok, server_options: opts}
  end

  describe "run a node" do
    @tag :skip
    test "smoke test", %{server_options: server_options} do
      {:ok, _} = Server.start_server(9999, server_options)
    end

    @tag :skip
    test "run a node with custom certificate", %{server_options: server_options} do
      {_, k} = :crypto.generate_key(:eddsa, :ed25519)

      CertUtils.generate_self_signed_certificate(k,
        keyfile: "priv/j.pem",
        certfile: "priv/j_cert.pem"
      )

      opts = server_options ++ [certfile: ~c"priv/j_cert.pem", keyfile: ~c"priv/j.pem"]

      {:ok, _} = Server.start_server(9999, opts)
    end
  end
end
