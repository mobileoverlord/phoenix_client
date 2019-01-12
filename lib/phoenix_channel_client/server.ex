defmodule PhoenixChannelClient.Server do
  use GenServer
  require Logger

  alias PhoenixChannelClient.Socket

  @default_timeout 5_000
  @rejoin_interval 1_000

  def start_link(sender, opts, genserver_opts \\ []) do
    with {:ok, pid} <- GenServer.start_link(__MODULE__, {sender, opts}, genserver_opts),
         {:ok, _} <- GenServer.call(pid, {:join, Keyword.get(opts, :join_params, %{})}) do
      {:ok, pid}
    else
      error ->
        error
    end
  end

  def stop(pid) do
    GenServer.call(pid, :leave)
  end

  def push(pid, event, payload, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(pid, {:push, event, payload}, timeout)
  end

  def init({sender, opts}) do
    socket = opts[:socket]
    topic = opts[:topic]
    join_params = opts[:join_params]
    rejoin_interval = opts[:rejoin_interval]

    Socket.channel_link(socket, self(), topic)

    {:ok,
     %{
       sender: sender,
       socket: socket,
       topic: topic,
       join_push: nil,
       join_ref: sender,
       rejoin_interval: @rejoin_interval,
       pushes: [],
       opts: opts,
       status: :closed
     }}
  end

  def handle_call({:join, params}, from, %{socket: socket} = state) do
    push = Socket.push(socket, state.topic, "phx_join", params)
    {:noreply, %{state | status: :joining, join_push: push, join_ref: from}}
  end

  def handle_call(:leave, _from, %{socket: socket} = state) do
    push = Socket.push(socket, state.topic, "phx_leave", %{})
    Socket.channel_unlink(socket, self(), state.topic)
    {:stop, :normal, :ok, %{state | status: :closed}}
  end

  def handle_call({:push, event, payload}, from, %{socket: socket} = state) do
    push = Socket.push(socket, state.topic, event, payload)
    {:noreply, %{state | pushes: [{from, push} | state.pushes]}}
  end

  def handle_call(call, from, state) do
    state.sender.handle_call(call, from, state)
  end

  def handle_cast(cast, state) do
    state.sender.handle_cast(cast, state)
  end

  def handle_info({:trigger, "phx_error", reason, _ref}, state) do
    state.sender.handle_close({:closed, reason}, %{state | status: :errored})
  end

  def handle_info({:trigger, "phx_close", reason, _ref}, %{status: :closing, socket: socket} = state) do
    # Socket.channel_unlink(socket, self(), state.topic)
    Process.send_after(self, :rejoin, state.rejoin_interval)
    state.sender.handle_close({:closed, reason}, %{state | status: :closed})
  end

  def handle_info(
        {:trigger, "phx_reply", %{"status" => status} = payload, ref},
        %{join_push: %{ref: ref}, join_ref: join_ref} = state
      ) do

    GenServer.reply(join_ref, {String.to_atom(status), Map.drop(payload, ["status"])})
    {:noreply, %{state | status: :joined}}
  end

  def handle_info(
        {:trigger, "phx_reply", %{"response" => response, "status" => status}, ref},
        state
      ) do

    state =
      case Enum.split_with(state.pushes, fn {_, push} -> push.ref == ref end) do
        {[{from_ref, _push}], pushes} ->
          GenServer.reply(from_ref, {String.to_atom(status), response})
          %{state | pushes: pushes}

        {[], _} ->
          state
      end
    {:noreply, state}
  end

  def handle_info({:trigger, event, payload, _ref}, state) do
    state.sender.handle_in(event, payload, state)
  end

  def handle_info(:rejoin, %{status: status, join_push: push, socket: socket} = state)
    when status != :joining and push != nil do

    Socket.push(socket, push.topic, "phx_join", push.payload)
    {:noreply, %{state | status: :joining}}
  end

  def handle_info(:rejoin, state) do
    {:noreply, state}
  end

  def handle_info(message, state) do
    state.sender.handle_info(message, state)
  end
end
