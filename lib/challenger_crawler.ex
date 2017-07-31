defmodule RiotApi.ChallengerCrawler do
  use GenServer
  require Logger

  @moduledoc """
  """

  @doc """
  """

  def start_link do
    config = %{}
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def get_challenger_players(page) do
    result = HTTPotion.get("http://www.leagueofgraphs.com/de/rankings/summoners/euw/page-"<>Integer.to_string(page))
             |> Map.get(:body)
    [_, table|_] = String.split(result, "<table class=\"data_table\">")
    [table_comp|_] = String.split(table, "</table>")
    File.write!("test.txt",table_comp)
    String.split(table_comp,"<tr>")
    |> Enum.drop(2)
    |> Enum.map(fn(tr) -> parse_tr(tr) end)
    |> Enum.filter(fn(name) -> name != [] end)
  end

  def get_challenger_till_place(number) do
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

end
