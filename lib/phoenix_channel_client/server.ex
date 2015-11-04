defmodule Phoenix.Channel.Client.Server do
  use GenServer
  require Logger

  @default_timeout 5_000

  def start_link(sender, opts) do
    GenServer.start_link(__MODULE__, {sender, opts})
  end

  def join(pid, params \\ %{}) do
    Logger.debug "Call Join"
    GenServer.call(pid, {:join, params})
  end

  def leave(pid, opts \\ []) do
    GenServer.call(pid, {:leave, opts})
  end

  def cancel_push(pid, push_ref) do
    GenServer.call(pid, {:cancel_push, push_ref})
  end

  def push(pid, event, payload, opts \\ []) do
    timeout =  opts[:timeout] || @default_timeout
    GenServer.call(pid, {:push, event, payload, timeout})
  end

  def init({sender, opts}) do
    socket = opts[:socket]
    topic = opts[:topic]
    socket.channel_link(socket, self, topic)
    {:ok, %{
      sender: sender,
      socket: socket,
      topic: topic,
      join_push: nil,
      leave_push: nil,
      pushes: [],
      opts: opts,
      state: :closed
    }}
  end

  def handle_call({:join, params}, from, %{socket: socket} = state) do
    #Logger.debug "Join Channel: #{state.topic}"
    push = socket.push(socket, state.topic, "phx_join", params)
    {:reply, push, %{state | state: :joining, join_push: push}}
  end

  def handle_call({:leave, opts}, _from, %{socket: socket} = state) do
    push = socket.push(socket, state.topic, "phx_leave", %{})
    if opts[:brutal] == true do
      #Logger.debug "Brutal Leave"
      socket.channel_unlink(socket, self, state.topic)
      chan_state = :closed
    else
      chan_state = :closing
    end
    {:reply, :ok, %{state | state: chan_state, leave_push: push}}
  end

  def handle_call({:push, event, payload, timeout}, _from, %{socket: socket} = state) do
    push = socket.push(socket, state.topic, event, payload)
    timer = :erlang.start_timer(timeout, self(), push)
    {:reply, push, %{state | pushes: [{timer, push} | state.pushes]}}
  end

  def handle_call({:cancel_push, push_ref}, _from, %{pushes: pushes} = state) do
    {[{timer, _}], pushes} = Enum.partition(pushes, fn({_, %{ref: ref}}) ->
      ref == push_ref
    end)
    :erlang.cancel_timer(timer)
    {:reply, :ok, %{state | pushes: pushes}}
  end

  def handle_info({:trigger, "phx_error", reason, ref} = payload, state) do
    state.sender.handle_close({:closed, reason}, %{state | state: :errored})
  end

  def handle_info({:trigger, "phx_close", reason, ref} = payload, %{state: :closing} = state) do
    state.socket.channel_unlink(state.socket, self, state.topic)
    state.sender.handle_close({:closed, reason}, %{state | state: :closed})
  end

  def handle_info({:trigger, "phx_reply", %{"status" => status} = payload, ref}, %{join_push: %{ref: join_ref}} = state) when ref == join_ref do
    state.sender.handle_reply({String.to_atom(status), :join, payload, ref}, %{state | state: :joined})
  end

  def handle_info({:trigger, "phx_reply", %{"response" => response, "status" => status}, ref}, state) do
    state.sender.handle_reply({String.to_atom(status), response, ref}, state)
  end

  def handle_info({:trigger, event, payload, ref} = p, state) do
    #Logger.debug "Trigger: #{inspect p}"
    state.sender.handle_in(event, payload, state)
  end

  # Push timer expired
  def handle_info({:timeout, timer, push}, %{pushes: pushes} = state) do
    {[{_, push}], pushes} = Enum.partition(pushes, fn({ref, _}) ->
      ref == timer
    end)

    state.sender.handle_reply({:timeout, push.event, push.ref}, %{state | pushes: pushes})
  end

end
