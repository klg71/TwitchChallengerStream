defmodule RiotApi do
  use GenServer
  require Logger

  @moduledoc """
  Documentation for RiotApi.
  """

  @doc """
  Handles querying of playing summoners and all other method that correspond to the RiotApi
  """

  def start_link(summoner_file) do
    champions = File.read!("champions.txt")
                |> Poison.decode!()
                |> Map.get("data")
                |> Enum.map(fn({champion,%{"id" => id}}) -> {id, champion} end)
                |> Enum.reduce(%{},fn({id, champion}, acc) -> Map.put(acc, id, champion) end)
    config = %{
      :summoner_file => summoner_file,
      :updated => ~N[2000-01-01 00:00:00],
      :summoners => [],
      :champions => champions
    }
    IO.inspect(config)
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    Process.send_after(self(), :update, 5_000)
    RiotApi.Bot.send_message("Updating in 5 seconds")
    {:ok, config}
  end

  def handle_cast(:update_playing_summoners, config) do
    {:noreply, update_playing_summoners(config)}
  end

  def handle_cast({:updated_summoners, summoners}, config) do
    Logger.info("Updated summoner list")
    new_config = Map.put(config, :updated, NaiveDateTime.utc_now())
                 |> Map.put(:summoners, summoners)
    {:noreply, new_config}
  end

  def handle_cast(:empty_summoners, config) do
    Logger.info("Emptieing summoner list")
    new_config= Map.put(config, :summoners, [])
    {:noreply, new_config}
  end

  def handle_call(:get_playing_summoners, _from, config) do
    {:reply, Map.get(config, :summoners, []), config}
  end

  def handle_call(:get_champions, _from, config) do
    {:reply, Map.get(config, :champions), config}
  end


  def handle_info(:check_game, config) do
    Logger.info("Check if game has ended")
    is_match_ended(Map.get(config.currentgame,"gameId"), Map.get(config.currentgame, "gameStartTime"))
    {:noreply, config}
  end

  def handle_cast(:update, config) do
    Task.async(fn->update_playing_summoners(config) end)
    {:noreply,config}
  end

  def handle_info(:update, config) do
    Task.async(fn->update_playing_summoners(config) end)
    {:noreply,config}
  end

  def handle_info(_, config) do
   {:noreply, config}
  end
  
  def query_players(filename) do
    {:ok, content} = File.read(filename)
    {:ok, player_ids} = content |> String.split("\r\n")
                         |> Enum.map(&RiotApi.get_summoner_id(&1))
                         |> Poison.encode(pretty: true)
    File.write("ids.json", player_ids)
  end

  def get_summoner_id("") do
    %{}
  end
  
  def get_summoner_id(summoner) do
    answer = url()<>"/lol/summoner/v3/summoners/by-name/"<>summoner<>"?api_key="<>key()
         |> RiotApi.ApiRequest.do_request
    case answer do
       %{"status" => %{"status_code" => 404}} -> []
       %{"status" => %{"status_code" => 500}} -> []
       id -> 
         %{accountid: Map.get(id,"accountId"), id: Map.get(id,"id"), name: summoner}
    end
  end
  defp update_playing_summoners(config) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), config.updated)
    cond do
      diff > 200 ->
        Logger.info "Get List of playing challengers"
        summoners = File.read!(config.summoner_file) 
          |> Poison.decode!
          |> get_matches_for_summoners()
        Process.send_after(self(), :update, 500_000)
        GenServer.cast(__MODULE__, {:updated_summoners, summoners})
      true ->
        Logger.info "Dont update, list is refreshed"
    end
  end

  def update_summoners do
    GenServer.cast(__MODULE__, :update)
  end

  def get_playing_summoners do
    GenServer.call(__MODULE__, :get_playing_summoners)
  end

  def empty_summoners() do
    GenServer.cast(__MODULE__,:empty_summoners)
  end

  def get_matches_for_summoners([head|tail]) do
  Logger.info("Remaining: "<>Integer.to_string(Enum.count(tail)))
    {:ok, match} = url()<>"/lol/spectator/v3/active-games/by-summoner/"<>URI.encode(Integer.to_string(Map.get(head, "id")))<>"?api_key="<>key() 
         |> RiotApi.ApiRequest.do_request
    result = case match do
       %{"status" => %{"status_code" => 404}} -> []
       %{"status" => %{"status_code" => 500}} -> []
       result ->
        case check_match_ended(gameid) do
          false -> 
            extract_games(result, gameid, observer_key, match)
          true -> 
            get_matches_for_summoners(tail)
        end
    end
    reduce_summoners_to_query(tail,result)
  end

  def check_match_ended(gameid) do
    {:ok, id} = url()<>"/lol/match/v3/matches/"<>URI.encode(Integer.to_string(gameid))<>"?api_key="<>key() 
         |> RiotApi.ApiRequest.do_request
    case id do
       %{"status" => %{"status_code" => 404}} -> false
       %{"status" => %{"status_code" => 500}} -> false
       _ -> true
     end     
  end

  defp extract_games(match) do
    gameid = Map.get(match, "gameId")
    observer_key = get_in(match,["observers", "encryptionKey"])
    Map.get(match, "participants")
            |> Enum.map(fn(%{"summonerId" => id, "summonerName" => name})->%{gameid: gameid,observer_key: observer_key, id: id, name: name, match: match} end)
            |> Enum.filter(fn(%{id: id}) -> Enum.any?([head|tail], fn(%{"id"=>chall_id}) -> chall_id == id end) end)
  end

  defp reduce_summoners_to_query(remaining,result) do
    case Enum.filter(remaining, fn (%{"id"=>id}) ->not id in Enum.map(result, &(&1.id)) end) do
      [] -> result
      reduced -> result++get_matches_for_summoners(reduced)
    end
  end

  defp url do
    Application.fetch_env!(:riot_api, :url)
  end

  defp key do
    Application.fetch_env!(:riot_api, :riot_key)
  end

  def get_champions do
    GenServer.call(__MODULE__, :get_champions)
  end

end
