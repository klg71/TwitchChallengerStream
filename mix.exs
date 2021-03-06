defmodule RiotApi.Mixfile do
  use Mix.Project

  def project do
    [app: :riot_api,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [
      extra_applications: [:logger, :cowboy, :plug],
      applications: [:httpotion,],
      mod: {RiotApi.Bot.Application, []},
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:httpotion, "~> 3.0.2"},
      {:poison, "~> 3.1"},
      {:exirc, "~> 1.0.1"},
      {:cowboy, "~> 1.0.3"},
      {:plug, "~> 1.0"},
      {:timber, "~> 2.5"},
	    {:html_entities, "~> 0.3"},
      {:ex_doc, "~> 0.11", only: :dev},
    ]
  end
end
