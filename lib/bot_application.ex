
defmodule RiotApi.Bot.Application do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = [
      worker(RiotApi, ["ids.json"]),
      worker(RiotApi.Bot, [%{:nick => "klg71"}]),
      worker(RiotApi.Votes, [%{}]),
      worker(RiotApi.Twitch, []),
      worker(RiotApi.ChallengerCrawler, []),
      worker(RiotApi.WebServer, []),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sequence.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
