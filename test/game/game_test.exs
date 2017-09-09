alias Punting.Game

defmodule Punting.GameTest do
  use ExUnit.Case

  test "new game has zero active players" do
    {:ok, game} = start_supervised({Game, {"sample", 2}})

    active_count = GenServer.call(game, {:activecount})
    assert active_count == 0
  end

  test "game starts after last player joins" do
    {:ok, game} = start_supervised({Game, {"sample", 3}})
    assert :waiting == GenServer.call(game, {:join, {self(), 0, "First"}})
    assert :waiting == GenServer.call(game, {:join, {self(), 1, "Second"}})
    assert :starting == GenServer.call(game, {:join, {self(), 2, "Last"}})
  end
  
end
