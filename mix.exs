defmodule Jamixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :jamixir,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Jamixir, []},
      extra_applications: [:logger, :mnesia]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test, :full_test], runtime: false},
      {:mox, "~> 1.2.0", only: [:test, :full_test], elixir: "~> 1.17"},
      {:ex_machina, "~> 2.8.0", only: [:test, :full_test]},
      {:excoveralls, "~> 0.18.3", only: [:test, :full_test]},
      {:httpoison, "~> 2.2.1", only: [:test, :full_test]},
      {:quicer, github: "emqx/quic", tag: "0.1.0"},
      {:x509, git: "https://github.com/jamixir/x509.git", branch: "master"},
      {:blake2, "~> 1.0"},
      {:ex_keccak, "~> 0.7.4"},
      {:rustler, "~> 0.34.0"},
      {:dotenv, "~> 3.1.0"},
      {:temp, "~> 0.4"},
      {:jamixir_vm, git: "https://github.com/jamixir/jamixir-vm.git", branch: "main"},
      {:cubdb, "~> 2.0.2"},
      {:muontrap, "~> 1.0"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/test_vectors"]
  defp elixirc_paths(:full_test), do: ["lib", "test/support", "test/test_vectors"]
  defp elixirc_paths(_), do: ["lib"]

  def aliases do
    [
      "test.full": "cmd MIX_ENV=full_test mix test --only full_vectors",
      "test.tiny": "cmd mix test --only tiny_vectors"
    ]
  end
end
