alias Punting.TcpServer
alias Punting.TcpServer.PlayerSupervisor

defmodule Punting.TcpServerTest do
  use ExUnit.Case
  
  @moduletag :functional

  test "handshake captures player name" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, _pid} = start_supervised({TcpServer, {4, "sample"}})

    {_socket, received} = connect_and_handshake("test runner")
    assert Poison.decode!(received) == %{"you" => "test runner"}
  end

  test "game state sent to all players" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, _pid} = start_supervised({TcpServer, {2, "sample"}})

    # each player should get the game state once all players have connected
    {socket1, _resp1} = connect_and_handshake("punter1")
    {socket2, _resp2} = connect_and_handshake("punter2")

    game1_msg = recv_msg(socket1)
    game2_msg = recv_msg(socket2)
    
    game1 = Poison.decode!(game1_msg)
    game2 = Poison.decode!(game2_msg)

    assert Map.get(game1, "punters") == 2
    assert Map.get(game2, "punters") == 2
  end

  test "game can have variable number of players" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, _pid} = start_supervised({TcpServer, {3, "sample"}})

    {socket1, _resp1} = connect_and_handshake("punter1")
    {socket2, _resp2} = connect_and_handshake("punter2")

    {:error, :timeout} = recv_msg(socket1, 1000)
    {socket3, _resp3} = connect_and_handshake("punter3")
    Enum.each([socket1, socket2, socket3], fn socket ->
      assert Map.get(
        Poison.decode!(
          recv_msg(socket)), "punters") == 3, "player"
    end)
  end

  test "game loads map" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, _pid} = start_supervised({TcpServer, {1, "sample"}})

    {socket, _resp1} = connect_and_handshake("punter1")

    msg = recv_msg(socket)
    map = Map.get(Poison.decode!(msg), "map")

    assert Enum.count(Map.get(map, "sites")) == 8
    assert Enum.count(Map.get(map, "rivers")) == 12
    assert Enum.count(Map.get(map, "mines")) == 2
    assert Enum.member?(Map.get(map, "sites"), %{"id" => 5, "x" => 1.0, "y" => -2.0})
  end

  test "game status is Waiting for players before players connect" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, pid} = start_supervised({TcpServer, {2, "sample"}})

    assert "Waiting for punters. (0/2)" == GenServer.call(pid, {:status}, 10000)

    {socket, _received} = connect_and_handshake("test runner")
    recv_msg(socket)

    assert "Waiting for punters. (1/2)" == GenServer.call(pid, {:status})
  end

  test "game status is Starting before all players are ready" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, pid} = start_supervised({TcpServer, {2, "sample"}})
    
    {socket1, _received} = connect_and_handshake("test runner")
    {socket2, _received} = connect_and_handshake("test runner")

    recv_msg(socket1)
    recv_msg(socket2)

    assert "Starting" == GenServer.call(pid, {:status})
  end

  test "game status is In progress after all players are ready" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, pid} = start_supervised({TcpServer, {2, "sample"}})
    GenServer.cast(pid, {:subscribe_events, self()})

    {socket1, _resp1} = connect_and_handshake("punter1")
    {socket2, _resp2} = connect_and_handshake("punter2")

    %{"punter" => id1} = recv_msg(socket1) |> Poison.decode!
    IO.puts("Test: got map for 1")
    %{"punter" => id2} = recv_msg(socket2) |> Poison.decode!
    IO.puts("Test: got map for 2")

    send_json(socket1, %{ready: id1})
    IO.puts("Test: sent ready for 1")
    send_json(socket2, %{ready: id2})
    IO.puts("Test: sent ready for 2")
    event = receive do
        {:event, {:start}} -> :start
      after
        2_000 -> :test_timeout
      end
    assert event == :start

    assert "Game in progress." == GenServer.call(pid, {:status})
  end

  test "players are prompted to move in turn once all players are ready" do
    {:ok, _sup_pid} = start_supervised(PlayerSupervisor)
    {:ok, pid} = start_supervised({TcpServer, {2, "sample"}})
    GenServer.cast(pid, {:subscribe_events, self()})

    {socket1, _resp1} = connect_and_handshake("punter1")
    {socket2, _resp2} = connect_and_handshake("punter2")

    %{"punter" => id1} = recv_msg(socket1) |> Poison.decode!
    %{"punter" => id2} = recv_msg(socket2) |> Poison.decode!

    send_json(socket1, %{ready: id1})
    send_json(socket2, %{ready: id2})
    result = receive do
        {:event, {:start}} ->
          :ok
      after
        2_000 -> :test_timeout
      end
    assert result == :ok

    expected_prompt_1 = %{"move" => %{"moves" => [
      %{"pass" => %{"punter" => 0}},
      %{"pass" => %{"punter" => 1}}
      ]}}
    assert expected_prompt_1 == recv_msg(socket1) |> Poison.decode!

    move_1 = %{"claim" => %{"punter" => 0, "source" => 0, "target" => 1}}
    send_json(socket1, move_1)

    expected_prompt_2 = %{"move" => %{"moves" => [
      move_1,
      %{"pass" => %{"punter" => 1}}
      ]}}
    assert expected_prompt_2 == recv_msg(socket2) |> Poison.decode!
  end

  defp connect_and_handshake(player) do
    port = Application.get_env :punting_server, :port

    case :gen_tcp.connect('localhost', port,
      active: false, mode: :binary, packet: :raw) do
      {:ok, socket} ->    
        IO.puts("Test: connected.")

        send_json(socket, %{"me" => player})

        received = recv_msg(socket)
        IO.puts("Test: handshake complete.")
        {socket, received}
      {:error, error} ->
        flunk inspect(error)
    end
  end

  defp recv_msg(socket, timeout \\ 10000) do
    case :gen_tcp.recv(socket, 10, timeout) do
        {:ok, header} ->
            case Integer.parse(header) do
                {size, ":" <> start_of_data} ->
                    {:ok, rest_of_data} =
                        :gen_tcp.recv(socket, size - byte_size(start_of_data))
                        start_of_data <> rest_of_data
                _error ->
                    raise "Error: No message length"
            end
        {:error, error} ->
            {:error, error}
    end  
  end

  defp send_json(socket, msg) do
    send_msg(socket, Poison.encode!(msg))
  end
  defp send_msg(socket, json) do
    :gen_tcp.send(socket, "#{byte_size(json)}:#{json}")
  end
end