defmodule Phoenix.Channel.Client.Channel do
  use GenServer

  alias Phoenix.Channel.Client.Socket

  require Logger

  defstruct pid: nil, topic: "", params: %{}

  @timeout 5000

  alias Phoenix.Channel.Client.Push

  def start_link(opts) do
    case GenServer.start_link(__MODULE__, opts) do
      {:ok, pid} -> %__MODULE__{pid: pid, topic: opts[:topic], params: opts[:params]}
      err -> err
    end
  end

  def join(pid, params, opts \\ []) do
    timeout = opts[:timeout] || @timeout
    case GenServer.call(pid, {:join, params}, timeout) do
      :ok -> pid
      error -> {:error, error}
    end
  end

  def leave(pid, params, opts \\ []) do
    timeout = opts[:timeout] || @timeout
    GenServer.call(pid, {:leave, params}, timeout)
  end

  def on(pid, event, func) do
    GenServer.call(pid, {:on, event, func})
  end

  def on(%Push{channel: pid} = push, event, func) do
    GenServer.call(pid, {:receive, push, event, func})
  end

  def trigger(pid, event, payload, ref) do
    GenServer.cast(pid, {:trigger, event, payload, ref})
  end

  def init(opts) do
    {:ok, %{
      state: :closed,
      sock: opts[:sock],
      topic: opts[:topic],
      params: opts[:params],
      joined_once: false,
      bindings: [],
      join_push: %Push{},
      pushes: [],
      rejoin_timer_ref: nil,
      buffer: []
    }}
  end

  def handle_call({:join, params}, _from, %{sock: sock} = s) do
    Logger.debug "Channel Join: #{inspect s.topic}, #{inspect params}"
    Socket.push(sock, s.topic, "phx_join", params)
    {:reply, :ok, s}
  end

  def handle_call({:leave, params}, _from, %{sock: sock} = s) do
    Socket.push(sock, s.topic, "phx_leave", params)
    {:stop, s}
  end

  def handle_call({:on, event, func}, _from, %{bindings: bindings} = s) do
    {:reply, self, %{s | bindings: [{event, func} | bindings]}}
  end

  def handle_call({:receive, %Push{} = push, event, func}, _from, %{pushes: pushes} = s) do
    push = Push.on_receive push, event, func
    pushes = pushes
      |> Enum.reject(&(&1 == push))
    {:reply, push, %{s | pushes: [push | pushes]}}
  end

  def handle_call({:after, %Push{} = push, event, func}, _from, %{pushes: pushes} = s) do
    push = Push.on_after push, event, func
    pushes = pushes
      |> Enum.reject(&(&1 == push))
    {:reply, push, %{s | pushes: [push | pushes]}}
  end

  def handle_cast({:trigger, event, payload, ref}, s) do

    {:noreply, s}
  end

end
