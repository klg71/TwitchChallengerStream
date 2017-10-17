defmodule RiotApi.Stream do
    use GenServer
    use Logger

  @moduledoc """
  Documentation for RiotApi.Stream
  """

  @doc """
  Orchestration for Stream
  Handles whole start and stop of games. 
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
      :currentgame => %{},
      :champions => champions
    }
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    RiotApi.Bot.send_message("New game starts in 20s")
    Process.send_after(self(), :new_game, 20_000)
    {:ok, config}
  end

  def handle_info(:new_game, config) do
    summoners = RiotApi.get_playing_summoners()
                |> Enum.map(config.summoners, fn(%{:name => summoner_name}) -> summoner_name end)
    case RiotApi.Votes.get_votes_list(summoners)
      do
        [] ->
            open_game_without_votes(summoners)
      [{name,_vote}|_] ->
            open_game(name)
      end
    {:noreply, config}
  end

  defp open_game_without_votes(summoners) do
    case summoners do
        [] ->
            RiotApi.Bot.send_message("No summoners detected, trying agagin in 100 seconds")
            Process.send_after(self(), :new_game, 100_000)
        [h|_] ->
            RiotApi.Bot.send_message("No valid votes, Spectating first summoner!")
            open_game(h)
    end
  end

  defp open_game(summoner) do
      GenServer.cast(__MODULE__, {:open_game, summoner})
  end

  def handle_cast({:open_game, summoner}, config) do
    case Enum.find(config.summoners, fn(%{:name => summoner_name})->summoner_name == summoner end) do
      %{gameid: gameid, observer_key: key, match: match} ->
        start_game_spectation(gameid, key, summoner)
        new_config=Map.put(config, :currentgame, match)
        {:noreply, new_config}
      _ ->
        Logger.info("Summoner: "<>summoner<>" not found")
        {:noreply, config}
    end
  end

  defp start_game_spectation(gameid, key, summoner) do
        RiotApi.empty_summoners()
        Logger.info("Spectating game: "<>Integer.to_string(gameid)
        Task.async(fn -> RiotApi.Spectator.spectate_game(gameid, key) end)
        post_start_game_messages(summoner)
        start_in_game_listeners()
        RiotApi.Votes.reset_votes()
  end

  defp post_start_game_messages(summoner) do
        RiotApi.Bot.send_message("Spectating: "<>summoner<>" GLHF!")
        RiotApi.Twitch.send_feed_post("Spectating: "<>summoner<>" GLHF!")
        RiotApi.Twitch.send_channel_title("Spectating EUW Challenger: "<>summoner)
  end

  defp start_in_game_listeners() do
        Process.send_after(self(), :check_game, 10_000)
        Process.send_after(self(), :configure_game, 180_0000)
  end

  def handle_info(:configure_game, config) do
    shell = "league_spectator.exe"
    Logger.info(shell)
    _task = Task.async(fn -> shell |> String.to_char_list |> :os.cmd end)
    {:noreply, config}
  end

  def handle_info(:check_game, config) do
    Logger.info("Check if game has ended")
    is_match_ended(Map.get(config.currentgame,"gameId"), Map.get(config.currentgame, "gameStartTime"))
    {:noreply, config}
  end

  def is_match_ended(gameid, gameStartTime) do
    dateTimeGame = DateTime.from_unix(gameStartTime,:millisecond) 
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), DateTime.to_naive(dateTimeGame))
    cond do
      diff > 3600 -> 
          Process.send_after(self(), :end_game, 2_000)
      true ->
        is_match_ended_naturally?(gameid)
    end
  end

  defp is_match_ended_naturally?(gameid) do
    case RiotApi.check_match_ended(gameid) do
        false ->
            Process.send_after(self(), :check_game, 40_000)
        true ->
            Process.send_after(self(), :end_game, 200_000)
    end
  end

  def handle_info(:end_game, config) do
    Task.async(fn->RiotApi.Spectator.kill_game() end)
    RiotApi.Bot.send_message("GG!")
    RiotApi.Bot.send_message("Game ended! New game starts in 120s")
    RiotApi.Bot.send_message("Last chance to vote!")
    Process.send_after(self(), :new_game, 120_000)
    {:noreply, Map.put(config, :currentgame, %{})}
  end

  def handle_call(:get_current_game, _from, config) do
    {:reply, Map.get(config, :currentgame, %{}), config}
  end

end