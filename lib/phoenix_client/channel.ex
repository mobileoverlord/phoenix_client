defmodule PhoenixClient.Channel do
  use GenServer

  alias PhoenixClient.{Socket, Message}

  @default_timeout 5_000

  def child_spec({socket, topic, genserver_opts}) do
    %{
      id: genserver_opts[:id] || __MODULE__,
      start: {__MODULE__, :start_link, [socket, topic, genserver_opts]}
    }
  end

  def child_spec({socket, topic}) do
    child_spec({socket, topic, []})
  end

  def start_link(socket, topic, genserver_opts \\ []) do
    GenServer.start_link(__MODULE__, {socket, topic}, genserver_opts)
  end

  def stop(pid) do
    GenServer.call(pid, :leave)
    GenServer.stop(pid)
  end

  def join(pid, params \\ %{}) do
    GenServer.call(pid, {:join, params})
  end

  def leave(pid) do
    GenServer.call(pid, :leave)
  end

  def push(pid, event, payload, timeout \\ @default_timeout) do
    GenServer.call(pid, {:push, event, payload}, timeout)
  end

  def push_async(pid, event, payload) do
    GenServer.cast(pid, {:push, event, payload})
  end

  def init({socket, topic}) do
    {:ok,
     %{
       sender: nil,
       socket: socket,
       topic: topic,
       pushes: []
     }}
  end

  def handle_call({:join, params}, {pid, _ref} = from, %{socket: socket, topic: topic} = state) do
    Socket.channel_link(socket, self(), topic)

    push =
      Socket.push(socket, %Message{
        topic: topic,
        event: "phx_join",
        payload: params,
        channel_pid: self()
      })

    {:noreply, %{state | sender: pid, pushes: [{from, push} | state.pushes]}}
  end

  def handle_call(:leave, _from, %{socket: socket, topic: topic} = state) do
    Socket.channel_unlink(socket, self(), state.topic)

    Socket.push(socket, %Message{
      topic: topic,
      event: "phx_leave",
      payload: %{},
      channel_pid: self()
    })

    {:reply, :ok, state}
  end

  def handle_call({:push, event, payload}, from, %{socket: socket, topic: topic} = state) do
    push =
      Socket.push(socket, %Message{
        topic: topic,
        event: event,
        payload: payload,
        channel_pid: self()
      })

    {:noreply, %{state | pushes: [{from, push} | state.pushes]}}
  end

  def handle_cast({:push, event, payload}, %{socket: socket, topic: topic} = state) do
    message = %Message{topic: topic, event: event, payload: payload, channel_pid: self()}
    Socket.push(socket, message)
    {:noreply, state}
  end

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

  def handle_info(%Message{} = message, %{sender: pid, topic: topic} = state) do
    send(pid, %{message | channel_pid: pid, topic: topic})
    {:noreply, state}
  end
end
