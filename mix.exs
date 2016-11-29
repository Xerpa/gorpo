defmodule Gorpo.Mixfile do
  use Mix.Project

  def project do
    [app: :gorpo,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     dialyzer: [plt_add_apps: [:poison, :inets]]]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:poison, ">= 1.2.0"},
     {:dialyxir, "~> 0.4", only: [:dev]},
     {:ex_doc, "~> 0.13", only: [:dev]}]
  end

end
