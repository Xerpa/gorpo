defmodule Gorpo.Mixfile do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :gorpo,
      version: @version,
      elixir: ">= 1.2.0",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),

      dialyzer: [plt_add_apps: [:poison, :inets]],

      description: "Service discovery using Consul",
      package: package()
    ]
  end

  def application do
    [
      mod: {Gorpo, []},
      applications: [:logger]
    ]
  end

  defp deps do
    [
      {:poison, ">= 2.0.0"},
      {:dialyxir, ">= 0.5.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.17", only: :dev}
    ]
  end

  defp package do
    [
      maintainers: ["Diego Vinicius e Souza"],
      licenses: ["BSD 2-clause"],
      links: %{"GitHub" => "https://github.com/Xerpa/gorpo"},
      files: ["lib", "mix.exs", "README.md", "COPYING"]
    ]
  end
end
