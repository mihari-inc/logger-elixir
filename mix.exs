defmodule Mihari.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mihari/mihari-elixir"

  def project do
    [
      app: :mihari,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Mihari",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Mihari.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp description do
    "Open-source log collection and transport library for Elixir. " <>
      "Ship structured logs to any HTTP endpoint with batching, gzip compression, " <>
      "automatic retries, and an Elixir Logger backend."
  end

  defp package do
    [
      name: "mihari",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
