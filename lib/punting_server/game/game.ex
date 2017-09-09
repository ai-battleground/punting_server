defmodule Punting.Game do
    use GenServer
    defstruct ~w[players status name map workers moves listeners]a

    # Client
    def start_link(args) do
        GenServer.start_link(__MODULE__, args)
    end

    # Server
    def init({map, players}) do
        map_data = load_map(map)
        state = %{
            name: map, 
            map: map_data,
            players: players,
            status: "Waiting for punters. (0/#{players})",
            workers: %{},
            listeners: [],
        }
        {:ok, state}
    end

    def handle_call({:status}, _from, state) do
        {:reply, state.status, state}
    end

    def handle_call({:activecount}, _from, state) do
        {:reply, length(Map.keys(state.workers)), state}
    end

    def handle_call({:join, {worker, id, player}}, _from, state) do
        workers = state.workers |> Map.put(id, %{
            pid: worker,
            id: id,
            player: player,
            moves: []})

        player_count = length(Map.keys(workers))
        {result, status} = if player_count < state.players do
            {:waiting, "Waiting for punters. (#{player_count}/#{state.players})"}
        else
            GenServer.cast self(), {:begin, workers}
            {:starting, "Starting"}
        end

        {:reply, result, %{state | workers: workers, status: status}}
    end

    def handle_cast({:subscribe_events, pid}, state) do
        {:noreply, %{state | listeners: [pid | state.listeners]}}
    end

    def handle_cast({:begin, workers}, state) do
        Enum.each(Map.values(workers), fn %{pid: pid} ->
            GenServer.cast pid, {:begin, %{players: state.players, map: state.map}}
        end)
        {:noreply, state}
    end

    def handle_cast({:notify, event}, state) do
        IO.puts("Game: notifying #{length(state.listeners)} listeners: event #{inspect(event)}")
        Enum.each(state.listeners, fn l -> 
            send l, {:event, event}
        end)
        {:noreply, state}
    end

    def handle_cast({:ready, id}, state) do
        IO.puts("Game: Player #{id} is ready.")
        worker = state.workers |> find_worker(id)
        new_workers = flag_ready(worker, state.workers)
        new_status = if all_ready?(new_workers) do
            GenServer.cast self, {:notify, {:start}}
            send self(), {:nextmove}
            "Game in progress."
        else
            state.status
        end
        {:noreply, %{state | status: new_status, workers: new_workers}}
    end

    def handle_cast({:move, {:claim, claim}}, state) do
        punter = claim |> Map.get("punter")
        %{^punter => worker} = state.workers
        send self(), {:nextmove}
        {:noreply, %{state | 
            workers: state.workers 
                |> Map.replace(punter, 
                    %{worker | moves: [%{"claim" => claim} | worker.moves]})}}
    end

    def handle_info({:nextmove}, state) do
        choose_turn(state.workers)
        |> offer_move(moves(state.workers))
        {:noreply, state}
    end

    defp load_map(name) do
        :code.priv_dir(:punting_server)
        |> Path.join("maps")
        |> Path.join("#{name}.json")
        |> File.read!
        |> Poison.decode!
    end

    defp find_worker(workers, id) do
        %{^id => %{id: ^id} = worker} = workers
        worker
    end

    defp flag_ready(worker, workers) do
        flagged = worker |> Map.put_new(:ready, true)
        workers |> Map.replace(worker.id, flagged)
    end

    defp all_ready?(workers) do
        workers
        |> Map.values
        |> Enum.all?(fn w -> w[:ready] end)
    end

    defp choose_turn(workers) do
        first = workers |> Map.get(0)
        moves = first.moves
        turn = length(moves)
        Enum.find(Map.values(workers), first, fn w -> 
            length(w.moves) < turn 
        end)
    end

    defp moves(workers) do
        workers
        |> Map.values
        |> Enum.map(fn w -> 
            w.moves |> List.last
            || %{"pass" => %{"punter" => w.id}}
        end)
    end

    defp offer_move(worker, moves) do
        GenServer.cast worker.pid, {:offer, moves}
    end

end