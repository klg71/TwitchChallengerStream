defmodule RiotApi.WebServer do
  use Plug.Router
  require Logger

  plug Plug.Logger, log: :warn
  plug :match
  plug :dispatch

  @moduledoc """
  """

  @doc """
  """

  @positions ["top", "jungle", "mid", "bot", "support"]

  def init(options) do
    {:ok, champions} = File.read!("champions.txt")
                |> Poison.decode()
    options
  end


  def start_link do
    {:ok, _} = Plug.Adapters.Cowboy.http RiotApi.WebServer, []
  end


  defp get_matches do
    case RiotApi.get_playing_summoners() do
      [] -> []
      summoners ->
        summoners
        |> Enum.map(&(Map.get(&1.match, "participants")))
        |> Enum.map(&(Enum.map(&1,fn(%{"championId" => championId, "summonerName" => name, "teamId" => teamId})-> {name, championId, teamId} end)))
        |> Enum.map(&(Enum.sort(&1,fn({_, _, team1}, {_, _, team2}) -> team1<team2 end)))
        |> Enum.map(&(Enum.split(&1,5)))
        |> Enum.dedup()
    end
    
  end

  defp format_match({blue_team, red_team}) do
    header = "<table class=\"table table-borderless\">"
    footer = "</table>"
    champions = RiotApi.get_champions()
    
    blue = Enum.map(blue_team, fn({summoner, championid, _}) ->
      "<tr><td style=\"color: blue\">"<>summoner<>"</td><td>"<>Map.get(champions, championid)<>"</td></tr>"
    end)
    |> Enum.join("\r\n")

    red = Enum.map(red_team, fn({summoner, championid, _}) ->
      "<tr><td style=\"color: red\">"<>summoner<>"</td><td>"<>Map.get(champions, championid)<>"</td></tr>"
    end)
    |> Enum.join("\r\n")
  
    "<tr><td>"<>header<>blue<>footer<>"</td><td>"<>header<>red<>footer<>"</td></tr>"    
  end

  defp format_votes(votes) do
    Map.to_list(votes)
    |> Enum.sort(fn ({_name1, vote1}, {_name2, vote2}) -> vote1>=vote2 end)
    |> Enum.map(fn({name, vote}) -> "<tr><td>"<>name <> "</td><td>" <> Integer.to_string(vote)<>"</td></tr>" end)
    |> Enum.join("\r\n")
  end

  get "/" do
    content = File.read!("index.html")
    conn
    |> send_resp(200, content)
    |> halt
  end

  get "/matches" do
    conn
    |> send_resp(200, get_matches()|>Enum.map(&(format_match(&1)))|>Enum.join("\r\n"))
    |> halt
  end

  get "/votes" do
    conn
    |> send_resp(200, RiotApi.Votes.get_votes() |> format_votes())
    |> halt
  end

  match _ do
    conn
    |> send_resp(404, "Nothing here")
    |> halt
  end

end
