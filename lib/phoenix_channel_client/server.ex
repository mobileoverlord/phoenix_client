defmodule PhoenixChannelClient.Server do
  use GenServer
  require Logger

  @default_timeout 5_000

  def start_link(sender, opts) do
    GenServer.start_link(__MODULE__, {sender, opts}, name: sender)
  end

  def join(pid, params \\ %{}, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(pid, {:join, params, timeout})
  end

  def leave(pid, opts \\ []) do
    GenServer.call(pid, {:leave, opts})
  end

  def cancel_push(pid, push_ref) do
    GenServer.call(pid, {:cancel_push, push_ref})
  end

  def push(pid, event, payload, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(pid, {:push, event, payload, timeout})
  end

  def init({sender, opts}) do
    socket = opts[:socket]
    topic = opts[:topic]
    socket.channel_link(socket, self(), topic)

    {:ok,
     %{
       sender: sender,
       socket: socket,
       topic: topic,
       join_push: nil,
       join_timer: nil,
       leave_push: nil,
       pushes: [],
       opts: opts,
       state: :closed
     }}
  end

  def handle_call({:join, params, timeout}, _from, %{socket: socket} = state) do
    push = socket.push(socket, state.topic, "phx_join", params)
    timer_ref = :erlang.start_timer(timeout, self(), push)
    {:reply, push, %{state | state: :joining, join_push: push, join_timer: timer_ref}}
  end

  def handle_call({:leave, opts}, _from, %{socket: socket} = state) do
    push = socket.push(socket, state.topic, "phx_leave", %{})

    chan_state =
      if opts[:brutal] == true do
        socket.channel_unlink(socket, self(), state.topic)
        :closed
      else
        :closing
      end

    {:reply, :ok, %{state | state: chan_state, leave_push: push}}
  end

  def handle_call({:push, event, payload, timeout}, _from, %{socket: socket} = state) do
    push = socket.push(socket, state.topic, event, payload)
    timer = :erlang.start_timer(timeout, self(), push)
    {:reply, push, %{state | pushes: [{timer, push} | state.pushes]}}
  end

  def handle_call({:cancel_push, push_ref}, _from, %{pushes: pushes} = state) do
    {[{timer, _}], pushes} =
      Enum.split_with(pushes, fn {_, %{ref: ref}} ->
        ref == push_ref
      end)

    :erlang.cancel_timer(timer)
    {:reply, :ok, %{state | pushes: pushes}}
  end

  def handle_call(call, from, state) do
    state.sender.handle_call(call, from, state)
  end

  def handle_cast(cast, state) do
    state.sender.handle_cast(cast, state)
  end

  def handle_info({:trigger, "phx_error", reason, _ref}, state) do
    state.sender.handle_close({:closed, reason}, %{state | state: :errored})
  end

  def handle_info({:trigger, "phx_close", reason, _ref}, %{state: :closing} = state) do
    state.socket.channel_unlink(state.socket, self(), state.topic)
    state.sender.handle_close({:closed, reason}, %{state | state: :closed})
  end

  def handle_info(
        {:trigger, "phx_reply", %{"status" => status} = payload, ref},
        %{join_push: %{ref: join_ref}} = state
      )
      when ref == join_ref do
    :erlang.cancel_timer(state.join_timer)

    state.sender.handle_reply({String.to_atom(status), :join, payload, ref}, %{
      state
      | state: :joined
    })
  end

  def handle_info(
        {:trigger, "phx_reply", %{"response" => response, "status" => status}, ref},
        state
      ) do
    case Enum.split_with(state.pushes, fn {_, push} -> push.ref == ref end) do
      {[{timer_ref, push}], pushes} ->
        :erlang.cancel_timer(timer_ref)

        state.sender.handle_reply({String.to_atom(status), push.topic, response, ref}, %{
          state
          | pushes: pushes
        })

      {[], []} ->
        {:noreply, state}
    end
  end

  def handle_info({:trigger, event, payload, _ref}, state) do
    state.sender.handle_in(event, payload, state)
  end

  def handle_info(:rejoin, %{join_push: nil} = state) do
    {:noreply, state}
  end

  def handle_info(:rejoin, state) do
    push = state.join_push
    state.socket.push(push.topic, "phx_join", push.payload)
    {:noreply, %{state | state: :joining}}
  end

  # Push timer expired

  def handle_info({:timeout, _timer, push}, %{join_push: push} = state) do
    state.sender.handle_reply({:timeout, :join}, state)
  end

  def handle_info({:timeout, timer, _push}, %{pushes: pushes} = state) do
    partition =
      Enum.split_with(pushes, fn {ref, _} ->
        ref == timer
      end)

    case partition do
      {[{_, push}], pushes} ->
        state.sender.handle_reply({:timeout, push.event, push.ref}, %{state | pushes: pushes})

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(message, state) do
    state.sender.handle_info(message, state)
  end
end
