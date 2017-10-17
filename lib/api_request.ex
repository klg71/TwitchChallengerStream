defmodule RiotApi.ApiRequest do
    use Logger

  @moduledoc """
  Documentation for RiotApi.ApiRequest
  """

  @doc """
  Contains methods for requesting the RiotApi. Handles Rate Limiting and parsing.
  """

  def do_request(url) do
    url
    |> do_url_request
    |> decode_json
    |> check_status_code
  end

  defp do_url_request(url) do
    headers = ["User-Agent": "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:56.0) Gecko/20100101 Firefox/56.0",
               "Accept-Charset": "application/x-www-form-urlencoded; charset=UTF-8",
               "Origin": "null",
               "X-Riot-Token": key(),
               "Accept-Language": "de,en-US;q=0.7,en;q=0.3",
              ]
    answer = URI.encode(url)
            |> HTTPotion.get(headers: headers)
  

    case answer do
      %{headers: %{hdrs: %{"retry-after" => seconds}}} ->
        Logger.info("Api rate exceeded waiting: "<>seconds<>"s")
        :timer.sleep(1_000*String.to_integer(seconds))
        do_request(url)
      %{message: "req_timedout"} -> 
        Logger.info("req_timeout trying again in 1s")
        :timer.sleep(1_000)
        do_request(url)
      %{message: "{:conn_failed, :error}"} -> 
        Logger.info("conn_failed")
        :timer.sleep(1_000)
        do_request(url)
      message -> message
    end
  end

  defp decode_json(answer) do
         answer  
         |> Map.get(:body)
         |> Poison.decode!
         |> check_status_code
  end

  defp check_status_code(answer) do
    case answer do
       %{"status" => %{"status_code" => 403}} -> 
         Logger.warn("Api key expired")
         []
       answer -> answer
    end
  end
end