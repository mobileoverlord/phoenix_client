defmodule PhoenixChannelClient.Socket do
  require Logger

  @reconnect 5000
  @heartbeat_interval 30000

  @callback handle_close(reply :: Tuple.t, state :: map) ::
              {:noreply, state :: map} |
              {:stop, reason :: term, state :: map}

  defmacro __using__(opts) do
    quote do
      require Logger
      unquote(config(opts))
      unquote(socket())
    end
  end

  defp config(opts) do
    quote do
      var!(otp_app) = unquote(opts)[:otp_app] || raise "socket expects :otp_app to be given"
      var!(config) = Application.get_env(var!(otp_app), __MODULE__)
    end
  end

  defp socket do
    quote unquote: false do
      use GenServer

      #alias PhoenixChannelClient.Push

      def start_link() do
        unquote(Logger.debug("Socket start_link #{__MODULE__}"))
        GenServer.start_link(PhoenixChannelClient.Socket, {unquote(__MODULE__), unquote(var!(config))}, name: __MODULE__)
      end

      def push(pid, topic, event, payload) do
        GenServer.call(pid, {:push, topic, event, payload})
      end

      def channel_link(pid, channel, topic) do
        GenServer.call(pid, {:channel_link, channel, topic})
      end

      def channel_unlink(pid, channel, topic) do
        GenServer.call(pid, {:channel_unlink, channel, topic})
      end

      def handle_close(_reason, state) do
        {:noreply, state}
      end

      defoverridable handle_close: 2
    end
  end

  ## Callbacks

  def init({sender, opts}) do
    send(self(), :connect)
    adapter = opts[:adapter] || PhoenixChannelClient.Adapters.WebsocketClient
    reconnect = opts[:reconnect] || true
    opts = Keyword.put_new(opts, :headers, [])
    heartbeat_interval = opts[:heartbeat_interval] || @heartbeat_interval
    {:ok, %{
      sender: sender,
      opts: opts,
      socket: nil,
      channels: [],
      reconnect: reconnect,
      heartbeat_interval: heartbeat_interval,
      state: :disconnected,
      adapter: adapter,
      ref: 0
    }}
  end

  def handle_call({:push, topic, event, payload}, _from, %{socket: socket} = state) do
    Logger.debug "Socket Push: #{inspect topic}, #{inspect event}, #{inspect payload}"
    Logger.debug "Socket State: #{inspect state}"
    ref = state.ref + 1
    push = %{topic: topic, event: event, payload: payload, ref: to_string(ref)}
    send(socket, {:send, push})
    {:reply, push, %{state | ref: ref}}
  end

  def handle_call({:channel_link, channel, topic}, _from, state) do
    channels = state.channels
    channels =
      if Enum.any?(channels, fn({c, t})-> c == channel and t == topic end) do
        channels
      else
        [{channel, topic} | state.channels]
      end
    {:reply, channel, %{state | channels: channels}}
  end

  def handle_call({:channel_unlink, channel, topic}, _from, state) do
    channels = Enum.reject(state.channels, fn({c, t}) -> c == channel and t == topic end)
    {:reply, channel, %{state | channels: channels}}
  end

  def handle_info(:connect, %{opts: opts} = state) do
    :crypto.start
    :ssl.start
    opts = Keyword.put(opts, :sender, self())

    Logger.debug "Url: #{inspect opts[:url]}"

    state =
      case state.adapter.open(opts[:url], opts) do
        {:ok, pid} ->
          Logger.debug "Connected Socket: #{inspect __MODULE__}"
          :erlang.send_after(state.heartbeat_interval, self(), :heartbeat)
          %{state | socket: pid, state: :connected}
        _ ->
          :erlang.send_after(@reconnect, self(), :connect)
          state
      end
    {:noreply, state}
  end

  def handle_info(:heartbeat, state) do
    ref = state.ref + 1
    send(state.socket, {:send, %{topic: "phoenix", event: "heartbeat", payload: %{}, ref: ref}})
    :erlang.send_after(state.heartbeat_interval, self(), :heartbeat)
    {:noreply, %{state | ref: ref}}
  end

  # New Messages from the socket come in here
  def handle_info({:receive, %{"topic" => topic, "event" => event, "payload" => payload, "ref" => ref}}, %{channels: channels} = state) do
    Enum.filter(channels, fn({_channel, channel_topic}) ->
      topic == channel_topic
    end)
    |> Enum.each(fn({channel, _}) ->
      send(channel, {:trigger, event, payload, ref})
    end)
    {:noreply, state}
  end

  def handle_info({:closed, reason}, state) do
    Logger.debug "Socket Closed: #{inspect reason}"
    Enum.each(state.channels, fn(channel)-> send(channel, {:trigger, :phx_error}) end)
    if state.reconnect == true, do: send(self(), :connect)
    state.sender.handle_close(reason, %{state | state: :disconnected})
  end

  def terminate(reason, _state) do
    Logger.debug("Socket terminating: #{reason}")
    :ok
  end

end
