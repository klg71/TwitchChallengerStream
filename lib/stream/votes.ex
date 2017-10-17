defmodule RiotApi.Votes do
  use GenServer
  use Logger

  @moduledoc """
  Documentation for RiotApi.Votes
  """

  @doc """
  Genserver for Voting. Saves votes per summoners.
  """

  def start_link(votes) do
    GenServer.start_link(__MODULE__, votes, name: __MODULE__)
  end

  def handle_cast({:vote, name}, votes) do
    new_votes = case votes do
      %{^name => votenumber} -> %{votes| name => votenumber+1}
      _ -> Map.merge(votes,%{name=> 1})
    end
    {:noreply, new_votes}
  end

  def handle_cast(:reset_votes, _votes) do
    RiotApi.Bot.send_message("Votes resetted!")
    {:noreply, %{}}
  end

  def handle_call(:get_votes, _from, votes) do
    {:reply, votes, votes}
  end

  def vote(name) do
    GenServer.cast(__MODULE__,{:vote, name})
  end

  def reset_votes do
    GenServer.cast(__MODULE__, :reset_votes)
  end

  def get_votes do
    GenServer.call(__MODULE__, :get_votes)
  end

  def get_votes_list(summoners) do
    RiotApi.Votes.get_votes
    |> Map.to_list
    |> Enum.sort(fn ({_name1, vote1}, {_name2, vote2}) -> vote1>=vote2 end)
    |> Enum.filter(fn({name, _vote}) -> name in summoners end)
  end
end
