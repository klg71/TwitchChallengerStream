defmodule RiotApi.WebServer do
  use Plug.Router
  require Logger

  plug Plug.Logger
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
    [%{"100" => %{
      "Nukeduck" => 24,
      "MagiFaker" => 76,
      "Reckless" => 63,
      "Ocelot" => 498,
      "Noway4u => 143"
    },
      "200" => %{
        "Magiefelix" => 420,
        "Svenskeren" => 33,
        "NoSkeren" => 42,
        "Marin" => 21,
        "Sola" => 201
      }
    }]
    
  end

  defp format_match(%{"100" => red_team, "200" => blue_team}) do
    header = "<table class=\"table table-borderless\">"
    footer = "</table>"
    champions = Map.get(RiotApi.get_champions() ,"data")
                |> Enum.map(fn({champion,%{"id": id}}) -> {id, champion} end)
                |> Enum.reduce(%{},fn({id, champion}, acc) -> Map.put(acc, id, champion) end)


    
    blue = Enum.map(blue_team, fn({summoner, championid}) ->
      "<tr><td style=\"color: blue\">"<>summoner<>"</td><td>"<>Map.get(champions, championid)<>"</td></tr>"
    end)
    |> Enum.join("\r\n")

    red = Enum.map(blue_team, fn({summoner, championid}) ->
      "<tr><td style=\"color: red\">"<>summoner<>"</td><td>"<>Map.get(champions, championid)<>"</td></tr>"
    end)
    |> Enum.join("\r\n")
  
    "<tr><td>"<>header<>blue<>footer<>"</td><td>"<>header<>red<>footer<>"</td></tr>"    
  end

  get "/" do
    content = File.read!("index.html")
              |> String.replace("#MATCHES#", get_matches()|>Enum.map(&(format_match(&1)))|>Enum.join("\r\n"))
    conn
    |> send_resp(200, content)
    |> halt
  end

  match _ do
    conn
    |> send_resp(404, "Nothing here")
    |> halt
  end

end
