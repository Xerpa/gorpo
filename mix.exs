defmodule Gorpo.Mixfile do
  use Mix.Project

  def project do
    [app: :gorpo,
     version: "0.1.0",
     elixir: ">= 1.2.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     dialyzer: [plt_add_apps: [:poison, :inets]]]
  end

  def application do
    [mod: {Gorpo, []},
     applications: [:logger]]
  end

  defp deps do
    [{:poison, ">= 1.2.0"},
     {:dialyxir, ">= 0.5.0", only: [:dev], runtime: false},
     {:ex_doc, ">= 0.14.3", only: [:dev]}]
  end

end
