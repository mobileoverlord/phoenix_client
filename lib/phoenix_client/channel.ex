defmodule PhoenixClient.Channel do
  use GenServer

  alias PhoenixClient.{Socket, ChannelSupervisor, Message}

  @timeout 5_000

  def child_spec({socket, topic, params}) do
    %{
      id: Module.concat(__MODULE__, topic),
      start: {__MODULE__, :start_link, [socket, topic, params]},
      restart: :temporary
    }
  end

  def child_spec({socket, topic}) do
    child_spec({socket, topic, %{}})
  end

  @doc false
  def start_link(socket, topic, params) do
    GenServer.start_link(__MODULE__, {socket, topic, params})
  end

  @doc false
  def stop(pid) do
    leave(pid)
  end

  @spec join(pid | atom, binary, map, non_neg_integer) :: {:ok, map, pid} | {:error, any}
  def join(socket, topic, params \\ %{}, timeout \\ @timeout)
  def join(nil, _topic, _params, _timeout), do: {:error, :socket_not_started}
  def join(socket, topic, params, timeout) when is_atom(socket) do
    join(Process.whereis(socket), topic, params, timeout)
  end
  def join(socket, topic, params, timeout) do
    if Process.alive?(socket) do
      case Socket.status(socket) do
        :connected ->
          case ChannelSupervisor.start_channel(socket, topic, params) do
            {:ok, pid} ->
              case GenServer.call(pid, :join, timeout) do
                {:ok, reply} ->
                  {:ok, reply, pid}
                error -> error
              end
          end

        status ->
          {:error, status}
      end
    else
      {:error, :socket_not_started}
    end
  end

  @spec leave(pid) :: :ok
  def leave(pid) do
    GenServer.call(pid, :leave)
    GenServer.stop(pid)
  end

  def push(pid, event, payload, timeout \\ @timeout) do
    GenServer.call(pid, {:push, event, payload}, timeout)
  end

  def push_async(pid, event, payload) do
    GenServer.cast(pid, {:push, event, payload})
  end

  # Callbacks
  @impl true
  def init({socket, topic, params}) do
    {:ok,
     %{
       sender: nil,
       socket: socket,
       topic: topic,
       params: params,
       pushes: []
     }}
  end

  @impl true
  def handle_call(:join, {pid, _ref} = from, %{socket: socket, topic: topic, params: params} = state) do
    case Socket.channel_join(socket, self(), topic, params) do
      {:ok, push} ->
        {:noreply, %{state | sender: pid, pushes: [{from, push} | state.pushes]}}
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:leave, _from, %{socket: socket, topic: topic} = state) do
    Socket.channel_leave(socket, self(), topic)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:push, event, payload}, from, %{socket: socket, topic: topic} = state) do
    push =
      Socket.push(socket, %Message{
        topic: topic,
        event: event,
        payload: payload
      })

    {:noreply, %{state | pushes: [{from, push} | state.pushes]}}
  end

  @impl true
  def handle_cast({:push, event, payload}, %{socket: socket, topic: topic} = state) do
    message = %Message{topic: topic, event: event, payload: payload, channel_pid: self()}
    Socket.push(socket, message)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{event: "phx_reply", ref: ref} = msg, %{pushes: pushes} = s) do
    pushes =
      case Enum.split_with(pushes, &(elem(&1, 1).ref == ref)) do
        {[{from_ref, _push}], pushes} ->
          %{"status" => status, "response" => response} = msg.payload
          GenServer.reply(from_ref, {String.to_atom(status), response})
          pushes

        {_, pushes} ->
          pushes
      end

    {:noreply, %{s | pushes: pushes}}
  end

  @impl true
  def handle_info(%Message{} = message, %{sender: pid, topic: topic} = state) do
    send(pid, %{message | channel_pid: pid, topic: topic})
    {:noreply, state}
  end
end
