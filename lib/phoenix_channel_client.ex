defmodule Phoenix.Channel.Client do
  use GenServer

  require Logger

  alias Phoenix.Channel.Client.Channel
  alias Phoenix.Channel.Client.Socket

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def connect(pid, url, headers \\ []) do
    GenServer.call(pid, {:connect, url, headers})
  end

  def channel(pid, topic, params \\ %{}) do
    GenServer.call(pid, {:add_channel, topic, params})
  end

  def init(opts) do
    {:ok, %{
      channels: [],
      socket: nil
    }}
  end

  def handle_call({:connect, url, headers}, _from, s) do
    case Socket.start_link(self, url, headers) do
      {:ok, sock} ->
        {:reply, {:ok, sock}, %{s | socket: sock}}
      err -> err
        {:stop, s}
    end
  end


  def handle_call({:add_channel, topic, params}, _from, s) do
    case Channel.start_link(sock: s.socket, topic: topic, params: params) do
      %Channel{pid: chan_pid} = chan ->
        {:reply, {:ok, chan_pid}, %{s | channels: [chan | s.channels]}}
      error -> error
        {:reply, {:error, error}}
    end
  end

  # New Messages from the socket come in here
  def handle_info(%{"topic" => topic, "event" => event, "payload" => payload, "ref" => ref} = msg, %{channels: channels} = s) do
    Logger.debug "Channels: #{inspect channels}"
    Enum.filter(channels, fn(%Channel{topic: chan_topic}) -> topic == chan_topic end)
      |> Enum.each(fn(%Channel{pid: pid}) -> Channel.trigger(pid, event, payload, ref) end)
    {:noreply, s}
  end
end
