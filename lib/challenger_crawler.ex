defmodule RiotApi.ChallengerCrawler do
  use GenServer
  require Logger

  @moduledoc """
  Documentation for RiotApi.ChallengerCrawler
  """

  @doc """
  Contains methods to parse challengers from leagueofgraphs.com
  """

  def start_link do
    config = %{}
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def handle_cast({:get_challenger_till_place, place, callback}, config) do
    challengers = get_challenger_till_place(place)
    callback.(challengers)
    {:noreply, config}
  end

  defp get_challenger_players(page) do
  
	Logger.info "get ranking page "<>Integer.to_string(page)
    result = HTTPotion.get("https://www.leagueofgraphs.com/de/rankings/summoners/euw/page-"<>Integer.to_string(page))
             |> Map.get(:body)
    [_, table|_] = String.split(result, "<table class=\"data_table\">")
    [table_comp|_] = String.split(table, "</table>")
    String.split(table_comp,"<tr>")
    |> Enum.drop(2)
    |> Enum.map(fn(tr) -> parse_tr(tr) end)
    |> Enum.filter(fn(name) -> name != [] end)
	|> Enum.map(fn(name) -> HtmlEntities.decode(name) end)
  end

  defp get_challenger_till_place(number) do
    pages = div(number,100)+1
    1..pages |> Enum.to_list |> Enum.reduce([], fn(page, acc) -> acc++get_challenger_players(page) end)
    |> Enum.slice(0, number)
  end

  defp parse_tr(tr) do
    case String.split(tr,"<span class=\"name\">") do
      [_,name_begin|_] -> 
        [name|_] = String.split(name_begin, "</span>")
        name
      _ -> []
    end
  end

  def get_challengers(place, callback) do
    GenServer.cast(__MODULE__, {:get_challenger_till_place, place, callback})
  end
  
  def write_challengers_to_file(challengers) do
	file_content = Enum.reduce(challengers, fn(challenger, listed)->listed<>challenger<>"\r\n" end)
    File.write("ids.txt", file_content)
	Logger.info "Challengers written to file"
  end
  
  def update_challengers(place) do
	GenServer.cast(__MODULE__, {:get_challenger_till_place, place, &RiotApi.ChallengerCrawler.write_challengers_to_file/1})
  end

end
