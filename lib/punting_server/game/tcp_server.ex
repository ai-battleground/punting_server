alias Punting.TcpServer.PlayerConnection
alias Punting.TcpServer.PlayerSupervisor

defmodule Punting.TcpServer do
    use GenServer
    defstruct ~w[socket ip port name map status players workers listeners]a

    # Server 

    def init({ip, port, players, map}) do
        map_data = load_map(map)
        origin_state = %{
            socket: nil,
            ip: ip, 
            port: port, 
            name: map, 
            map: map_data, 
            status: "Waiting for punters. (0/#{players})",
            players: players, 
            workers: %{},
            listeners: []
            }
        case listen(ip, port) do
            {:ok, listen_socket} ->
                send self(), {:accept, listen_socket}
                {:ok, %{origin_state | socket: listen_socket}}
            {:error, :eaddrinuse} ->
                {:ok, origin_state, 1000}
        end
    end

    def handle_call({:status}, _from, state) do
        {:reply, state.status, state}
    end

    def handle_cast({:subscribe_events, pid}, state) do
        {:noreply, %{state | listeners: [pid | state.listeners]}}
    end

    def handle_cast({:handshake_completed, {:ok, worker, id, player}}, state) do
        workers = state.workers |> Map.put(id, %{
            pid: worker,
            id: id,
            player: player})

        player_count = length(Map.keys(workers))
        status = if player_count < state.players do
            send self(), {:accept, state.socket}
            "Waiting for punters. (#{player_count}/#{state.players})"
        else
            GenServer.cast self(), {:begin, workers}
            "Starting"
        end

        {:noreply, %{state | workers: workers, status: status}}
    end

    def handle_cast({:handshake_completed, {:timeout}}, state) do
        send self(), {:accept, state.socket}
        {:noreply, state}
    end

    def handle_cast({:begin, workers}, state) do
        Enum.each(Map.values(workers), fn %{pid: pid} ->
            send pid, {:begin, %{players: state.players, map: state.map}}
        end)
        {:noreply, state}
    end

    def handle_cast({:ready, id}, state) do
        IO.puts("TcpServer: Player #{id} is ready.")
        worker = %{^id => %{id: id}} = state.workers
        |> Map.put_new(:ready, true)
        new_workers = state.workers |> Map.replace(id, worker)
        new_status = if all_ready(new_workers) do
            send self(), {:notify, {:start}}
            "Game in progress."
        else
            state.status
        end
        {:noreply, %{state | status: new_status, workers: new_workers}}
    end

    def handle_info({:timeout, new_state}, _state) do
        IO.puts("TcpServer: Address was in use, trying to listen again.")
        case listen(new_state.ip, new_state.port) do
            {:ok, listen_socket} ->
                send self(), {:accept, listen_socket}
                {:ok, %{new_state | socket: listen_socket}}
            {:error, :eaddrinuse} ->
                {:stop, "Couldn't listen on port #{new_state.port}: Address already in use"}
        end
    end

    def handle_info({:accept, listen_socket}, state) do
        case :gen_tcp.accept(listen_socket, 250) do
            {:ok, client_socket} ->
                id = state.workers |> Map.keys |> length
                {:ok, worker_pid} = PlayerSupervisor.start_worker(
                    id, client_socket, self())
                {:ok, _} = GenServer.call(worker_pid, {:await_handshake, 2000})
            {:error, :timeout} ->
                send self(), {:accept, listen_socket}
        end

        {:noreply, state}
    end

    def handle_info({:notify, event}, state) do
        IO.puts("TcpServer: notifying #{length(state.listeners)} listeners: event #{inspect(event)}")
        Enum.each(state.listeners, fn l -> send l, {:event, event} end)
        {:noreply, state}
    end

    defp listen(ip, port) do
        :gen_tcp.listen(port, [:binary,{:packet, 0},{:active,false},{:ip,ip}])
    end

    defp all_ready(workers) do
        workers
        |> Map.values
        |> Enum.all?(fn w -> w[:ready] end)
    end

    defp load_map(name) do
        :code.priv_dir(:punting_server)
        |> Path.join("maps")
        |> Path.join("#{name}.json")
        |> File.read!
        |> Poison.decode!
    end

    # Client

    def start_link({players, map}) do
        GenServer.start_link(__MODULE__,
            {
                Application.get_env(:punting_server, :ip, {127,0,0,1}), 
                Application.get_env(:punting_server, :port, 7190),
                players,
                map
            })
    end

end

defmodule Punting.TcpServer.PlayerSupervisor do
    use Supervisor

    def init(:ok) do
        children = [
            worker(PlayerConnection, [])
        ]

        supervise(children, strategy: :simple_one_for_one)
    end

    def start_link(_args) do
        Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
    end

    def start_worker(id, socket, server) do
        Supervisor.start_child(__MODULE__, [{id, socket, server}])
    end    
end