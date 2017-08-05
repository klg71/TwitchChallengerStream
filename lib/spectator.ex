
defmodule RiotApi.Spectator do
  use GenServer
  require Logger

  @moduledoc """
  Documentation for RiotApi.
  """

  @doc """
  Hello world.

  """
  def spectate_game(gameid, observer_key) do
    current_path = File.cwd!
    File.cd("C:\\Riot Games\\League of Legends\\RADS\\projects\\lol_game_client\\releases\\0.0.1.123\\deploy")
    shell = "start \"\" \"League of Legends.exe\" \"8394\" \"LoLLauncher.exe\" \"\" \"spectator spectator.euw1.lol.riotgames.com:80 "<>observer_key<>" "<>Integer.to_string(gameid)<>" EUW1\" \"-UseRads\""
    Logger.info(shell)
    _task = Task.async(fn -> shell |> String.to_char_list |> :os.cmd end)
    :timer.sleep(1000)
    File.cd(current_path)
  end

  def kill_game do
    shell = "taskkill /IM \"League of Legends.exe\""
    Logger.info(shell)
    _task = Task.async(fn -> shell |> String.to_char_list |> :os.cmd end)
  end
end
