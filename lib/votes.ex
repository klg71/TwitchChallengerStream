defmodule RiotApi.Votes do
  use GenServer

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

  def handle_cast(:reset_votes, votes) do
    {:noreply, %{}}
  end

  def handle_call(:get_votes, _from, _votes) do
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
end
