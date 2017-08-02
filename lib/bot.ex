defmodule RiotApi.Bot do
  use GenServer
  require Logger

  defmodule Config do
    defstruct server:  "irc.twitch.tv",
              port:    6667,
              pass:    "oauth:z3g1uw8wp4hul95q9ngha319j4jrj2",
              nick:    "klg71",
              user:    "klg71",
              name:    nil,
              channel: "#klg71",
              client:  nil,
              commands: []

    def from_params(params) when is_map(params) do
      Enum.reduce(params, %Config{}, fn {k, v}, acc ->
        case Map.has_key?(acc, k) do
          true  -> Map.put(acc, k, v)
          false -> acc
        end
      end)
    end
  end

  alias ExIrc.Client
  alias ExIrc.SenderInfo

  def start_link(%{:nick => _nick} = params) when is_map(params) do
    config = Config.from_params(params)
    GenServer.start_link(__MODULE__, [config], name: __MODULE__)
  end

  def init([config]) do
    RiotApi.update_playing_summoners()
    # Start the client and handler processes, the ExIrc supervisor is automatically started when your app runs
    {:ok, client}  = ExIrc.start_link!()

    # Register the event handler with ExIrc
    Client.add_handler client, self()

    # Connect and logon to a server, join a channel and send a simple message
    Logger.debug "Connecting to #{config.server}:#{config.port}"
    Client.connect! client, config.server, config.port

    commands = File.read!("commands.txt")
               |> String.split("\r\n")
               |> Enum.map(&(String.split(&1, ":")))
               |> Enum.map(fn([command, text]) -> {command, text} end)
    IO.inspect(commands)

    {:ok, %Config{config | :client => client, :commands => commands}}
  end

  def handle_info({:connected, server, port}, config) do
    Logger.debug "Connected to #{server}:#{port}"
    Logger.debug "Logging to #{server}:#{port} as #{config.nick}.."
    Client.logon config.client, config.pass, config.nick, config.user, config.name
    {:noreply, config}
  end
  def handle_info(:logged_in, config) do
    Logger.debug "Logged in to #{config.server}:#{config.port}"
    Logger.debug "Joining #{config.channel}.."
    Client.join config.client, config.channel
    {:noreply, config}
  end
  def handle_info(:disconnected, config) do
    Logger.debug "Disconnected from #{config.server}:#{config.port}"
    {:stop, :normal, config}
  end
  def handle_info({:joined, channel}, config) do
    Logger.debug "Joined #{channel}"
    Client.msg config.client, :privmsg, config.channel, "Voting online!"
    {:noreply, config}
  end
  def handle_info({:names_list, channel, names_list}, config) do
    names = String.split(names_list, " ", trim: true)
            |> Enum.map(fn name -> " #{name}\n" end)
    Logger.info "Users logged in to #{channel}:\n#{names}"
    {:noreply, config}
  end
  def handle_info({:received, msg, %SenderInfo{:nick => nick}, channel}, config) do
    Logger.info "#{nick} from #{channel}: #{msg}"
    handle_message(msg, config)
    {:noreply, config}
  end
  def handle_info({:mentioned, msg, %SenderInfo{:nick => nick}, channel}, config) do
    Logger.warn "#{nick} mentioned you in #{channel}"
    case String.contains?(msg, "hi") do
      true ->
        reply = "Hi #{nick}!"
        Client.msg config.client, :privmsg, config.channel, reply
        Logger.info "Sent #{reply} to #{config.channel}"
      false ->
        :ok
    end
    {:noreply, config}
  end

  def handle_info({:received, msg, %SenderInfo{:nick => nick}}, config) do
    Logger.warn "#{nick}: #{msg}"
    reply = "Hi!"
    Client.msg config.client, :privmsg, nick, reply
    Logger.info "Sent #{reply} to #{nick}"
    {:noreply, config}
  end

  # Catch-all for messages you don't care about
  def handle_info(_msg, config) do
    {:noreply, config}
  end

  def handle_call({:switch_channel, new_channel}, _from, config) do
    Client.part(config.client, config.channel)
    Client.join(config.client, new_channel)
    {:reply, :ok, %{config|:channel => new_channel}}
  end

  def handle_call(:get_channel, _from, config) do
    {:reply, config.channel, config}
  end

  def handle_cast({:send_message, msg}, config) do
    Client.msg config.client, :privmsg, config.channel, msg
    {:noreply, config}
  end

  def handle_cast({:add_command, command, text}, config) do
    
    {:noreply, %{config | :commands => config.commands ++ [{command, text}]}}
  end

  def send_message(msg) do
    GenServer.cast(__MODULE__,{:send_message, msg})
  end

  def add_command(command, text) do
    GenServer.cast(__MODULE__, {:add_command, command, text})
  end

  def terminate(_, config) do
    # Quit the channel and close the underlying client connection when the process is terminating
    Client.quit config.client, "Voting offline"
    Client.quit config.client, "Goodbye, cruel world."
    Client.stop! config.client
    :ok
  end

  defp handle_message(msg, config) do
    case msg do
      "!vote "<> name -> RiotApi.Votes.vote(name)
      "!votes" -> Client.msg config.client, :privmsg, config.channel, format_votes(RiotApi.Votes.get_votes())
      "!summoners" -> Client.msg config.client, :privmsg, config.channel, format_players(RiotApi.get_playing_summoners())
      "!current" -> Client.msg config.client, :privmsg, config.channel, format_game(RiotApi.get_current_game())
      "!help" -> Client.msg config.client, :privmsg, config.channel, format_help()
      command -> Client.msg config.client, :privmsg, config.channel, match_commands(command, config)
    end
  end

  defp match_commands(command, %Config{:commands => commands}) do
    keys = Enum.map(commands, fn({command_key, _text}) -> command_key end)
    cond do
      command in keys ->
        Enum.find(commands, fn({command_key, text}) -> command == command_key end)
        |> elem(1)
      true ->
        ""
    end
  end

  defp format_votes(votes) do
    IO.inspect(votes)
    Map.to_list(votes)
    |> Enum.sort(fn ({_name1, vote1}, {_name2, vote2}) -> vote1>=vote2 end)
    |> Enum.map(fn({name, vote}) -> name <> ": " <> Integer.to_string(vote) end)
    |> Enum.join(", ")
  end

  defp format_players({summoners, updated}) do
    IO.inspect(summoners)
    players = Enum.map(summoners, fn(%{:name=>summoner}) -> summoner end)
    |> Enum.join(", ") 
    players <>" updated "<>Integer.to_string(NaiveDateTime.diff(NaiveDateTime.utc_now(),updated))<>" seconds ago"
  end

  defp format_game(%{"participants" => participants}) do
    participants
    |> Enum.map(fn(%{"summonerName"=>name,"teamId" => team})-> {name, team} end)
    |> Enum.sort(fn({_name1,team1}, {_name2, team2}) -> team1>team2 end)
    |> Enum.map(fn({name,_team}) -> name end)
    |> Enum.split(5)
    |> Tuple.to_list
    |> Enum.map(&(Enum.join(&1, ", ")))
    |> Enum.join(" <> ")
  end

  defp format_game(%{}) do
    "No game running"
  end

  defp format_help do
    "!vote x: vote for player x"<>"!votes: display current votes" <> "!summoners: display current available summoners" <> "!current: display current game info"
  end

  def switch_channel(channelname) do
    GenServer.call(__MODULE__, {:switch_channel, channelname})
  end

  def get_channel do
    GenServer.call(__MODULE__, :get_channel)
  end
end
