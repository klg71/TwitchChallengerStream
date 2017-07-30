defmodule RiotApi.Twitch do
  use GenServer
  require Logger

  @moduledoc """
  """

  @doc """
  """

  defp url do
    Application.fetch_env!(:riot_api, :twitch_url)
  end

  defp clientid do
    Application.fetch_env!(:riot_api, :twitch_clientid)
  end

  defp oauth do
    Application.fetch_env!(:riot_api, :twitch_oauth)
  end

  defp name do
    Application.fetch_env!(:riot_api, :twitch_name)
  end

  defp id do
    Application.fetch_env!(:riot_api, :twitch_id)
  end


  def start_link do
    config = %{}
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end


  def handle_cast({:send_feed_post, message}, config) do

    url = url()<>"feed/"<>Integer.to_string(id())<>"/posts?client_id="<>clientid()<>"&share=true"
    content=%{"content": message}
    headers = [
      'Client-ID': clientid(),
      'Accept': "application/vnd.twitchtv.v5+json",
      'Content-Type': "application/json",
      'Authorization': "OAuth "<> oauth()
    ]
    HTTPotion.post(url, [body: Poison.encode!(content), headers: headers])
    {:noreply, config}
  end

  def handle_cast({:set_channel_title, title}, config) do
    
    url = url()<>"channels/"<>Integer.to_string(id())<>"?client_id="<>clientid
    IO.inspect(url)

    content=%{"channel": %{"status": title, "game": "League of Legends"}}
    headers = [
      'Client-ID': clientid(),
      'Accept': "application/vnd.twitchtv.v5+json",
      'Content-Type': "application/json",
      'Authorization': "OAuth " <> oauth()
    ]
    %HTTPotion.Response{body: body} = HTTPotion.put(url, [body: Poison.encode!(content), headers: headers])
    Logger.info(body)
    {:noreply, config}
  end


  def send_feed_post(message) do
    GenServer.cast(__MODULE__, {:send_feed_post, message})
  end

  def send_channel_title(title) do
    GenServer.cast(__MODULE__, {:set_channel_title, title})
  end
end
