defmodule Phoenix.Channel.Client do

  defmacro __using__(_opts) do
    quote do
      unquote(server)
    end
  end

  defp server do
    quote do
      use GenServer
      require Logger

    end
  end

  @moduledoc """
  {:ok, client} = Client.start_link url: "ws://127.0.0.1:4000/socket"

  """

  # use GenServer
  #
  # require Logger
  #
  # alias Phoenix.Channel.Client.Channel
  # alias Phoenix.Channel.Client.Socket
  # alias Phoenix.Channel.Client.Push
  #
  # def start_link do
  #   GenServer.start_link(__MODULE__, [])
  # end
  #
  # def connect(pid, url, headers \\ []) do
  #   GenServer.call(pid, {:connect, url, headers})
  # end
  #
  # def channel(socket, topic, params \\ %{}) do
  #   GenServer.call(socket.client, {:channel, socket, topic, params})
  # end
  #
  # def join(%Channel{} = chan, mod, params \\ %{}) do
  #   Channel.join(chan, mod, params)
  # end
  #
  # def init(opts) do
  #   {:ok, %{
  #     channels: []
  #   }}
  # end
  #
  # def handle_call({:connect, url, headers}, _from, s) do
  #   case Socket.start_link(sender: self, url: url, headers: headers) do
  #     %Socket{} = sock ->
  #       {:reply, {:ok, put_in(sock.client, self)}, s}
  #     error -> error
  #       {:reply, {:error, error}, s}
  #   end
  # end
  #
  # def handle_call({:channel, socket, topic, params}, _from, s) do
  #   case Channel.start_link(socket: socket, topic: topic, params: params) do
  #     %Channel{pid: chan_pid} = chan ->
  #       {:reply, chan_pid, %{s | channels: [chan | s.channels]}}
  #     error -> error
  #       {:reply, {:error, error}}
  #   end
  # end
  #
  # # def handle_cast({:join, %Channel{} = chan, mod}, s) do
  # #   Socket.push chan.socket.pid, chan.topic, "phx_join", %{}
  # #   {:noreply, s}
  # # end
  #
  #
  # # New Messages from the socket come in here
  # def handle_info(%{"topic" => topic, "event" => event, "payload" => payload, "ref" => ref} = msg, %{channels: channels} = s) do
  #   Logger.debug "Channels: #{inspect channels}"
  #   Enum.filter(channels, fn(%Channel{topic: chan_topic}) -> topic == chan_topic end)
  #     |> Enum.each(fn(%Channel{pid: pid}) -> Channel.trigger(pid, event, payload, ref) end)
  #   {:noreply, s}
  # end
end
