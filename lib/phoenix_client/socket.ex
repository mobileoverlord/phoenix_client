defmodule PhoenixClient.Socket do
  require Logger

  @heartbeat_interval 30_000
  @reconnect_interval 60_000
  @default_transport PhoenixClient.Transports.Websocket

  alias PhoenixClient.Message

  def child_spec({opts, genserver_opts}) do
    %{
      id: genserver_opts[:id] || __MODULE__,
      start: {__MODULE__, :start_link, [opts, genserver_opts]}
    }
  end

  def child_spec(opts) do
    child_spec({opts, []})
  end

  def start_link(opts, genserver_opts \\ []) do
    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def push(pid, %Message{} = message) do
    GenServer.call(pid, {:push, message})
  end

  def channel_link(pid, channel, topic) do
    GenServer.call(pid, {:channel_link, channel, topic})
  end

  def channel_unlink(pid, channel, topic) do
    GenServer.call(pid, {:channel_unlink, channel, topic})
  end

  def status(pid) do
    GenServer.call(pid, :status)
  end

  ## Callbacks

  def init(opts) do
    :crypto.start()
    :ssl.start()

    transport = opts[:transport] || @default_transport

    json_library = Keyword.get(opts, :json_library, Jason)

    reconnect? = Keyword.get(opts, :reconnect?, true)
    url = Keyword.get(opts, :url, "")
    opts = Keyword.put_new(opts, :headers, [])
    heartbeat_interval = opts[:heartbeat_interval] || @heartbeat_interval
    reconnect_interval = opts[:reconnect_interval] || @reconnect_interval

    transport_opts =
      Keyword.get(opts, :transport_opts, [])
      |> Keyword.put(:sender, self())

    Process.flag(:trap_exit, true)

    send(self(), :connect)

    {:ok,
     %{
       opts: opts,
       url: url,
       json_library: json_library,
       params: Keyword.get(opts, :params, %{}),
       channels: [],
       reconnect: reconnect?,
       heartbeat_interval: heartbeat_interval,
       reconnect_interval: reconnect_interval,
       reconnect_timer: nil,
       status: :disconnected,
       transport: transport,
       transport_opts: transport_opts,
       transport_pid: nil,
       queue: :queue.new(),
       ref: 0
     }}
  end

  def handle_call({:push, %Message{} = message}, _from, state) do
    ref = state.ref + 1
    push = %{message | ref: to_string(ref)}

    send(self(), :flush)
    {:reply, push, %{state | ref: ref, queue: :queue.in(push, state.queue)}}
  end

  def handle_call({:channel_link, channel, topic}, _from, state) do
    channels = state.channels
    Process.monitor(channel)

    channels =
      if Enum.any?(channels, fn {c, t} -> c == channel and t == topic end) do
        channels
      else
        [{channel, topic} | state.channels]
      end

    {:reply, channel, %{state | channels: channels}}
  end

  def handle_call({:channel_unlink, channel, topic}, _from, state) do
    {unlink_channels, channels} =
      Enum.split_with(state.channels, fn {c, t} -> c == channel and t == topic end)

    Enum.each(unlink_channels, &(elem(&1, 1) |> Process.demonitor()))
    {:reply, channel, %{state | channels: channels}}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_info({:connected, transport_pid}, %{transport_pid: transport_pid} = state) do
    :erlang.send_after(state.heartbeat_interval, self(), :heartbeat)
    {:noreply, %{state | status: :connected}}
  end

  def handle_info(:heartbeat, %{status: :connected} = state) do
    ref = state.ref + 1

    %Message{topic: "phoenix", event: "heartbeat", ref: ref}
    |> transport_send(state)

    :erlang.send_after(state.heartbeat_interval, self(), :heartbeat)
    {:noreply, %{state | ref: ref}}
  end

  def handle_info(:heartbeat, state) do
    {:noreply, state}
  end

  # New Messages from the transport_pid come in here
  def handle_info({:receive, message}, state) do
    transport_receive(message, state)
    {:noreply, state}
  end

  def handle_info(:flush, %{status: :connected} = state) do
    state =
      case :queue.out(state.queue) do
        {:empty, _queue} ->
          state

        {{:value, message}, queue} ->
          transport_send(message, state)
          :erlang.send_after(100, self(), :flush)
          %{state | queue: queue}
      end

    {:noreply, state}
  end

  def handle_info(:flush, state) do
    :erlang.send_after(100, self(), :flush)
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    url =
      URI.parse(state.url)
      |> Map.put(:query, URI.encode_query(state.params))
      |> to_string

    {:ok, pid} = state[:transport].open(url, state[:transport_opts])
    {:noreply, %{state | transport_pid: pid, reconnect_timer: nil}}
  end

  # Handle Errors in the transport and channels
  def handle_info({:closed, reason, transport_pid}, %{transport_pid: transport_pid, reconnect_timer: nil} = state) do
    {:noreply, close(reason, state)}
  end

  def handle_info({:EXIT, transport_pid, reason}, %{transport_pid: transport_pid, reconnect_timer: nil} = state) do
    state = %{state | transport_pid: nil}
    {:noreply, close(reason, state)}
  end

  # Unlink a channel if the process goes down
  def handle_info({:DOWN, _monitor_ref, :process, pid, _reason}, %{channels: channels} = s) do
    channels = Enum.reject(channels, &(elem(&1, 0) == pid))
    {:noreply, %{s | channels: channels}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp transport_receive(message, state) do
    %{channels: channels, json_library: json_library} = state
    decoded = Message.decode!(message, json_library)

    channels
    |> Enum.filter(&elem(&1, 1) == decoded.topic)
    |> Enum.each(&elem(&1, 0) |> send(decoded))
  end

  defp transport_send(message, %{transport_pid: pid, json_library: json_library}) do
    send(pid, {:send, Message.encode!(message, json_library)})
  end

  defp close(reason, state) do
    state = %{state | status: :disconnected}
    message = %Message{event: close_event(reason), payload: %{reason: reason}}

    for {pid, _channel} <- state.channels do
      send(pid, message)
    end

    if state.reconnect and state.reconnect_timer == nil do
      timer_ref = Process.send_after(self(), :connect, state.reconnect_interval)
      %{state | reconnect_timer: timer_ref}
    else
      state
    end
  end

  defp close_event(:normal), do: "phx_close"
  defp close_event(_), do: "phx_error"
end
