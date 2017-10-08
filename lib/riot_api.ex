defmodule RiotApi do
  use GenServer
  require Logger

  @moduledoc """
  Documentation for RiotApi.
  """

  @doc """
  Hello world.



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
      :currentgame => %{},
      :champions => champions
    }
    IO.inspect(config)
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
        GenServer.cast(__MODULE__,:empty_summoners)
        Logger.info("Spectating game: "<>Integer.to_string gameid)
        Task.async(fn -> RiotApi.Spectator.spectate_game(gameid, key) end)
        Process.send_after(self(), :check_game, 10_000)
        Process.send_after(self(), :configure_game, 180_0000)
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
    Logger.info("Updated summoner list")
    new_config=Map.put(config, :updated, NaiveDateTime.utc_now()) |> Map.put(:summoners, summoners)
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

  def handle_call(:get_current_game, _from, config) do
    {:reply, Map.get(config, :currentgame, %{}), config}
  end

  def handle_call(:get_champions, _from, config) do
    {:reply, Map.get(config, :champions), config}
  end


  def handle_info(:check_game, config) do
    Logger.info("Check if game has ended")
    is_match_ended(Map.get(config.currentgame,"gameId"))
    {:noreply, config}
  end

  def handle_info(:end_game, config) do
        Task.async(fn->RiotApi.Spectator.kill_game() end)
        RiotApi.Bot.send_message("GG!")
        RiotApi.Bot.send_message("Game ended! New game starts in 120s")
        RiotApi.Bot.send_message("Last chance to vote!")
        Process.send_after(self(), :update, 1_000)
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
              RiotApi.Twitch.send_feed_post("Spectating: "<>h<>" GLHF!")
              RiotApi.Twitch.send_channel_title("Spectating EUW Challenger: "<>h)
              open_game(h)
          end
      [{name,_vote}|_] ->
        RiotApi.Bot.send_message("Spectating: "<>name<>" GLHF!")
        RiotApi.Twitch.send_feed_post("Spectating: "<>name<>" GLHF!")
        RiotApi.Twitch.send_channel_title("Spectating EUW Challenger: "<>name)
        open_game(name)
      end
    {:noreply, config}
  end

  def handle_info(:configure_game, config) do
    shell = "league_spectator.exe"
    Logger.info(shell)
    _task = Task.async(fn -> shell |> String.to_char_list |> :os.cmd end)
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
    File.write("ids.json", player_ids)
  end

  def get_summoner_id("") do
    %{}
  end

  def do_request(url) do
	headers = ["User-Agent": "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:56.0) Gecko/20100101 Firefox/56.0", 
					#"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
					"Accept-Charset": "application/x-www-form-urlencoded; charset=UTF-8",
					"Origin": "null",
					"X-Riot-Token": key(),
					"Accept-Language": "de,en-US;q=0.7,en;q=0.3",
					]
	answer = URI.encode(url)
         |> HTTPotion.get(headers: headers)
	
  #IO.inspect(answer)

	case answer do
    %{headers: %{hdrs: %{"retry-after" => seconds}}} ->
      Logger.info("Api rate exceeded waiting: "<>seconds<>"s")
        :timer.sleep(1_000*String.to_integer(seconds))
        do_request(url)
		%{message: "req_timedout"} -> 
			Logger.info("req_timeout")
         :timer.sleep(1_000)
			do_request(url)
		%{message: "{:conn_failed, :error}"} -> 
			Logger.info("conn_failed")
         :timer.sleep(1_000)
			do_request(url)
		message -> message
	end
  end
  
  def get_summoner_id(summoner) do
  
	answer = url()<>"/lol/summoner/v3/summoners/by-name/"<>summoner<>"?api_key="<>key()
         |> do_request
	IO.inspect(answer)
	{:ok, match} = answer	 
         |> Map.get(:body)
		 |> Poison.decode
	 case match do
       %{"status" => %{"status_code" => 404}} -> []
       %{"status" => %{"status_code" => 403}} -> 
         Logger.warn("Api key expired")
         []
       %{"status" => %{"status_code" => 429}} -> 
	   
		 IO.inspect(Map.get(answer, :headers))
         Logger.info("API Rate exceeded waiting 10 seconds")
         :timer.sleep(10_000)
         get_summoner_id(summoner)
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

  def get_playing_summoners do
    GenServer.call(__MODULE__, :get_playing_summoners)
  end

  def get_current_game do
    GenServer.call(__MODULE__, :get_current_game)
  end


  def open_game(summoner) do
    GenServer.cast(__MODULE__, {:open_game, summoner})
  end

  def get_matches_for_summoners([head|tail]) do
	Logger.info("Remaining: "<>Integer.to_string(Enum.count(tail)))
    {:ok, match} = url()<>"/lol/spectator/v3/active-games/by-summoner/"<>URI.encode(Integer.to_string(Map.get(head, "id")))<>"?api_key="<>key() 
         |> do_request
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
        case check_match_ended(gameid) do
          false -> 
            Map.get(result, "participants")
            |> Enum.map(fn(%{"summonerId" => id, "summonerName" => name})->%{gameid: gameid,observer_key: observer_key, id: id, name: name, match: match} end)
            |> Enum.filter(fn(%{id: id}) -> Enum.any?([head|tail], fn(%{"id"=>chall_id}) -> chall_id == id end) end)
          true -> 
            get_matches_for_summoners(tail)
        end
    end
    case Enum.filter(tail, fn (%{"id"=>id}) ->not id in Enum.map(result, &(&1.id)) end) do
      [] -> result
      reduced -> result++get_matches_for_summoners(reduced)
    end
  end

  def check_match_ended(gameid) do
    {:ok, id} = url()<>"/lol/match/v3/matches/"<>URI.encode(Integer.to_string(gameid))<>"?api_key="<>key() 
         |> do_request
         |> Map.get(:body,"{\"status\":{\"status_code\": 429}}")
         |> Poison.decode 
    case id do
       %{"status" => %{"status_code" => 404}} ->
          false
       %{"status" => %{"status_code" => 429}} ->
         Logger.info("API Rate exceeded waiting 30 seconds")
         :timer.sleep(30_000)
         check_match_ended(gameid)
       %{"status" => %{"status_code" => 500}} -> false
       _ ->
        true
     end     
  end

  def is_match_ended(gameid) do
     case check_match_ended(gameid) do
       false ->
          Process.send_after(self(), :check_game, 30_000)
       true ->
          Process.send_after(self(), :end_game, 200_000)
     end
  end


  def get_match_info(matchid) do
    {:ok, match} = url()<>"/lol/match/v3/matches/"<>URI.encode(Integer.to_string(matchid))<>"?api_key="<>key() 
         |> do_request
         |> Map.get(:body,"{\"status\":{\"status_code\": 429}}")
         |> Poison.decode 
    match
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
