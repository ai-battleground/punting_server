defmodule Punting.TcpServer.PlayerConnection do
    use GenServer
    defstruct ~w[server id player socket open]a

    def init({id, socket, server}) do
        state = %__MODULE__{
            server: server,
            id: id,
            socket: socket,
            open: nil
        }
        send self(), {:recv, []}
        {:ok, state}
    end

    def handle_call({:await_handshake, timeout}, {from, _}, state) do
        send self(), {:await_open, from, System.os_time(:millisecond) + timeout}
        {:reply, {:ok, nil}, state}
    end

    def handle_cast({:move, moves}, state) do
        :gen_tcp.send(state.socket, encode(%{"move" => %{"moves" => moves}}))
        {:noreply, state}
    end

    def handle_info({:recv, _}, state) do

        case recv_msg(state.socket) do
            {:ok, msg} ->
                IO.puts("PlayerConnection: recv: #{msg}")
                send self(), parse(msg)
                send self(), {:recv, []}
                {:noreply, state}
            {:timeout, _} ->
                send self(), {:recv, []}
                {:noreply, state}
            {:error, error} ->
                IO.puts("PlayerConnection Error: #{error}")
                {:noreply, state}
        end
    end

    def handle_info({:handshake, %{player: player}}, state) do
        response = %{you: player}
        :gen_tcp.send(state.socket, encode(response))
        {:noreply, %{state | player: player, open: System.os_time(:millisecond)}}
    end

    def handle_info({:await_open, from, deadline}, state) do

        if deadline < System.os_time(:millisecond) do
            GenServer.cast(from, {:handshake_completed, {:timeout}})
            {:noreply, state}
        else
            case state.open do
                nil -> 
                    send self(), {:await_open, from, deadline}
                    {:noreply, state, :hibernate}
                _open -> 
                    GenServer.cast(from, 
                        {:handshake_completed, 
                            {:ok, self(), state.id, state.player}})
                    {:noreply, state}
            end
        end
    end

    def handle_info({:ready, %{id: id}}, state) do
        if id == state.id do
            GenServer.cast(state.server, {:ready, id})
        end
        {:noreply, state}
    end

    def handle_info({:begin, %{players: players, map: map}}, state) do
        :gen_tcp.send(state.socket, encode(%{
            punter: state.id,
            punters: players,
            map: map
        }))
        {:noreply, state}
    end

    defp parse(json) do
        case Poison.decode!(json) do
            %{"me" => player} ->
                {:handshake, %{player: player}}
            %{"ready" => id} ->
                {:ready, %{id: id}}
        end
    end

    defp encode(response) do
        json = Poison.encode!(response)
        "#{byte_size(json)}:#{json}"
    end

    defp recv_msg(socket, timeout \\ 200) do
      case :gen_tcp.recv(socket, 10, timeout) do
          {:ok, header} ->
            case Integer.parse(header) do
                {size, ":" <> start_of_data} ->
                  {:ok, rest_of_data} =
                    :gen_tcp.recv(socket, size - byte_size(start_of_data))
                    {:ok, start_of_data <> rest_of_data}
                  _error ->
                      raise "Error: No message length: #{inspect(header)}"
              end
          {:error, :timeout} ->
            {:timeout, ""}
          {:error, error} ->
            {:error, error}
      end  
    end

    # Client
    def start_link({id, socket, server}) do
        GenServer.start_link(__MODULE__, {id, socket, server})
    end
end