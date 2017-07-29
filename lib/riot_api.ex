defmodule RiotApi do
  use GenServer
  require Logger

  @moduledoc """
  Documentation for RiotApi.
  """

  @doc """
  Hello world.



  """
  @url ""
  @key ""

  def start_link(summoner_file) do
    config = %{:summoner_file => summoner_file, :updated => ~N[2000-01-01 00:00:00],:summoners => [], :currentgame => %{}}
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    Process.send_after(self(), :update, 5_000)
    RiotApi.Bot.send_message("New game starts in 20s")
    Process.send_after(self(), :new_game, 20_000)
    {:ok, config}
  end

  def handle_cast(:update_playing_summoners, config) do
    {:noreply, update_playing_summoners(config)}
  end

  def handle_cast({:open_game, summoner}, config) do
    case Enum.find(config.summoners, fn(%{:name => summoner_name})->summoner_name == summoner end) do
      %{gameid: gameid, observer_key: key, match: match} ->
        Logger.info(Integer.to_string gameid)
        Task.async(fn -> spectate_game(gameid, key) end)
        Process.send_after(self(), :check_game, 10_000)
        RiotApi.Votes.reset_votes()
        RiotApi.Bot.send_message("Votes resetted!")
        new_config=Map.put(config, :currentgame, match)
        {:noreply, new_config}
      _ ->
        Logger.info("Summoner: "<>summoner<>" not found")
        {:noreply, config}
    end
  end

  def handle_cast({:updated_summoners, summoners}, config) do
    new_config=Map.put(config, :updated, NaiveDateTime.utc_now()) |> Map.put(:summoners, summoners)
    {:noreply, new_config}
  end

  def handle_call(:get_playing_summoners, _from, config) do
    {:reply, {Map.get(config, :summoners, []), config.updated}, config}
  end

  def handle_call(:get_current_game, _from, config) do
    {:reply, Map.get(config, :currentgame, %{}), config}
  end


  def handle_info(:check_game, config) do
    Logger.info("Check if game has ended")
    is_match_ended(Map.get(config.currentgame,"gameId"))
    {:noreply, config}
  end

  def handle_info(:end_game, config) do
        Task.async(fn->kill_game() end)
        RiotApi.Bot.send_message("GG!")
        RiotApi.Bot.send_message("Game ended! New game starts in 120s")
        RiotApi.Bot.send_message("Last chance to vote!")
        Process.send_after(self(), :new_game, 120_000)
        {:noreply, Map.put(config, :currentgame, %{})}
  end

  def handle_info(:update, config) do
    Task.async(fn->update_playing_summoners(config) end)
    {:noreply,config}
  end

  def handle_info(:new_game, config) do
    summoners = Enum.map(config.summoners, fn(%{:name => summoner_name}) -> summoner_name end)
    case RiotApi.Votes.get_votes
    |> Map.to_list
    |> Enum.sort(fn ({_name1, vote1}, {_name2, vote2}) -> vote1>=vote2 end)
    |> Enum.filter(fn({name, _vote}) -> name in summoners end)
      do
        [] ->
          case summoners do
            [] ->
              RiotApi.Bot.send_message("No summoners detected, trying agagin in 100 seconds")
              Process.send_after(self(), :new_game, 100_000)
            [h|_] ->
              RiotApi.Bot.send_message("No valid votes, Spectating first summoner!")
              RiotApi.Bot.send_message("Spectating: "<>h<>" GLHF!")
              open_game(h)
          end
      [{name,_vote}|_] ->
        RiotApi.Bot.send_message("Spectating: "<>name<>" GLHF!")
        open_game(name)
      end
    {:noreply, config}
  end

  def handle_info(_, config) do
   {:noreply, config}
  end
  def query_players(filename) do
    {:ok, content} = File.read(filename)
    {:ok, player_ids} = content |> String.split("\r\n")
                         |> Enum.map(&RiotApi.get_summoner_id(&1))
                         |> Poison.encode(pretty: true)
    File.write("ids.txt", player_ids)
  end

  def get_summoner_id("") do
    %{}
  end

  def get_summoner_id(summoner) do
    {:ok, id} = url<>"/lol/summoner/v3/summoners/by-name/"<>(URI.encode(summoner))<>"?api_key="<>key 
         |> HTTPotion.get()
         |> Map.get(:body)
         |> Poison.decode
    %{accountid: Map.get(id,"accountId"), id: Map.get(id,"id"), name: summoner}
  end

  defp update_playing_summoners(config) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), config.updated)
    cond do
      diff > 300 ->
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

  def update_playing_summoners do
    GenServer.cast(__MODULE__, :update_playing_summoners)
  end


  def get_playing_summoners do
    GenServer.call(__MODULE__, :get_playing_summoners)
  end

  def get_current_game do
    GenServer.call(__MODULE__, :get_current_game)
  end


  def open_game(summoner) do
    GenServer.cast(__MODULE__, {:open_game, summoner})
  end

  def get_matches_for_summoners([head|[]]) do
    {:ok, match} = url<>"/lol/spectator/v3/active-games/by-summoner/"<>URI.encode(Integer.to_string(Map.get(head, "id")))<>"?api_key="<>key 
         |> HTTPotion.get()
         |> Map.get(:body)
         |> Poison.decode 
    gameid = Map.get(match, "gameId")
    observer_key = get_in(match,["observers", "encryptionKey"])
    result = case match do
      %{"status" => %{"status_code" => 404}} -> []
      %{"status" => %{"status_code" => 403}} -> 
        Logger.warn("Api key expired")
        []
      %{"status" => %{"status_code" => 429}} -> 
         Logger.info("API Rate exceeded waiting 10 seconds")
         :timer.sleep(10_000)
         get_matches_for_summoners([head|[]])
      %{"status" => %{"status_code" => 500}} -> []
      %{"gameMode"=>"MATCHED_GAME"} ->
         Map.get(match, "participants")
         |> Enum.map(fn(%{"summonerId" => id, "summonerName" => name})->%{gameid: gameid,observer_key: observer_key, summonerid: id, name: name, match: match} end)
         |> Enum.filter(fn(%{summonerid: id}) -> Enum.any?([head|[]], fn(%{"id"=>chall_id}) -> chall_id == id end) end)
      _ ->
        []
    end
    result
  end

  def get_matches_for_summoners([head|tail]) do
    {:ok, match} = url<>"/lol/spectator/v3/active-games/by-summoner/"<>URI.encode(Integer.to_string(Map.get(head, "id")))<>"?api_key="<>key 
         |> HTTPotion.get()
         |> Map.get(:body,"{\"status\":{\"status_code\": 429}}")
         |> Poison.decode 
    gameid = Map.get(match, "gameId")
    observer_key = get_in(match,["observers", "encryptionKey"])
    result = case match do
       %{"status" => %{"status_code" => 404}} -> []
       %{"status" => %{"status_code" => 403}} -> 
         Logger.warn("Api key expired")
         []
       %{"status" => %{"status_code" => 429}} -> 
         Logger.info("API Rate exceeded waiting 10 seconds")
         :timer.sleep(10_000)
         get_matches_for_summoners([head|tail])
       %{"status" => %{"status_code" => 500}} -> []
       result ->
         Map.get(result, "participants")
         |> Enum.map(fn(%{"summonerId" => id, "summonerName" => name})->%{gameid: gameid,observer_key: observer_key, id: id, name: name, match: match} end)
         |> Enum.filter(fn(%{id: id}) -> Enum.any?([head|tail], fn(%{"id"=>chall_id}) -> chall_id == id end) end)
    end
    reduced = Enum.filter(tail, fn (%{"id"=>id}) ->not id in Enum.map(result, &(&1.id)) end)
    result++get_matches_for_summoners(reduced)
  end

  def is_match_ended(gameid) do
    {:ok, id} = url<>"/lol/match/v3/matches/"<>URI.encode(Integer.to_string(gameid))<>"?api_key="<>key 
         |> HTTPotion.get()
         |> Map.get(:body)
         |> Poison.decode 
     case id do
       %{"status" => %{"status_code" => 404}} ->
          Process.send_after(self(), :check_game, 30_000)
       %{"status" => %{"status_code" => 429}} ->
         Logger.info("API Rate exceeded waiting 30 seconds")
          Process.send_after(self(), :check_game, 30_000)
       %{"status" => %{"status_code" => 500}} -> false
       _ ->
        Process.send_after(self(), :end_game, 200_000)
     end
  end

  def spectate_game(gameid, observer_key) do
    current_path = File.cwd!
    File.cd("C:\\Riot Games\\League of Legends\\RADS\\projects\\lol_game_client\\releases\\0.0.1.123\\deploy")
    IO.inspect(File.cwd!())
    shell = "start \"\" \"League of Legends.exe\" \"8394\" \"LoLLauncher.exe\" \"\" \"spectator spectator.euw1.lol.riotgames.com:80 "<>observer_key<>" "<>Integer.to_string(gameid)<>" EUW1\" \"-UseRads\""
    IO.inspect(shell)
    Logger.info(shell)
    _task = Task.async(fn -> shell |> String.to_char_list |> :os.cmd end)
    :timer.sleep(1000)
    File.cd(current_path)
  end

  def kill_game do
    shell = "taskkill /IM \"League of Legends.exe\""
    IO.inspect(shell)
    Logger.info(shell)
    _task = Task.async(fn -> shell |> String.to_char_list |> :os.cmd end)
  end
  

  def get_match_info(matchid) do
    {:ok, match} = url<>"/lol/match/v3/matches/"<>URI.encode(Integer.to_string(matchid))<>"?api_key="<>key 
         |> HTTPotion.get()
         |> Map.get(:body)
         |> Poison.decode 
    match
  end

  defp url do
    Application.fetch-env!(:riotapi, :url)
  end

  defp key do
    Application.fetch-env!(:riotapi, :riot_key)
  end



end
