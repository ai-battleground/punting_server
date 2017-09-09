alias Punting.TcpServer.PlayerConnection
alias Punting.TcpServer.PlayerSupervisor
alias Punting.Game

defmodule Punting.TcpServer do
    use GenServer
    defstruct ~w[socket ip port game]a

    # Server 

    def init({ip, port, players, map}) do
        {:ok, game} = Game.start_link({map, players})
        origin_state = %{
            socket: nil,
            ip: ip, 
            port: port, 
            game: game,
            }
        case listen(ip, port) do
            {:ok, listen_socket} ->
                GenServer.cast(self(), {:accept})
                {:ok, %{origin_state | socket: listen_socket}}
            {:error, :eaddrinuse} ->
                {:ok, origin_state, 1000}
        end
    end

    def handle_call({:status}, _from, state) do
        status = state.game |> GenServer.call({:status})
        {:reply, status, state}
    end

    def handle_cast({:subscribe_events, pid}, state) do
        GenServer.cast state.game, {:subscribe_events, pid}
        {:noreply, state}
    end

    def handle_cast({:handshake_completed, {:ok, worker, id, player}}, state) do
        gamestate = GenServer.call(state.game, {:join, {worker, id, player}})
        if gamestate == :waiting, do: GenServer.cast(self(), {:accept})
        {:noreply, state}
    end

    def handle_cast({:handshake_completed, {:timeout}}, state) do
        GenServer.cast(self(), {:accept})
        {:noreply, state}
    end

    def handle_cast({:ready, id}, state) do
        GenServer.cast(state.game, {:ready, id})
        {:noreply, state}        
    end

    def handle_cast({:accept}, state) do
        case :gen_tcp.accept(state.socket, 250) do
            {:ok, client_socket} ->
                playercount = GenServer.call(state.game, {:activecount})
                id = playercount 
                {:ok, worker_pid} = PlayerSupervisor.start_worker(
                    id, client_socket, self())
                {:ok, _} = GenServer.call(worker_pid, {:await_handshake, 2000})
            {:error, :timeout} ->
                GenServer.cast(self(), {:accept})
        end

        {:noreply, state}
    end

    def handle_cast({:move, _} = move, state) do
        GenServer.cast(state.game, move)
        {:noreply, state}
    end

    def handle_info({:timeout, new_state}, _state) do
        IO.puts("TcpServer: Address was in use, trying to listen again.")
        case listen(new_state.ip, new_state.port) do
            {:ok, listen_socket} ->
                GenServer.cast(self(), {:accept})
                {:ok, %{new_state | socket: listen_socket}}
            {:error, :eaddrinuse} ->
                {:stop, "Couldn't listen on port #{new_state.port}: Address already in use"}
        end
    end

    defp listen(ip, port) do
        :gen_tcp.listen(port, [:binary,{:packet, 0},{:active,false},{:ip,ip}])
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