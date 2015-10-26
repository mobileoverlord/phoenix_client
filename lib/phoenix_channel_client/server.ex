defmodule Phoenix.Channel.Client.Server do
  @callback handle_in(event :: String.t, payload :: map, state :: map) :: {:noreply, state :: map}
  @callback handle_reply(reply :: Tuple.t, state :: map) :: any
  @callback handle_close(reply :: Tuple.t, state :: map) :: any

  defmacro __using__(_opts) do
    quote do
      @behaviour Phoenix.Channel.Client.Server
      unquote(server)
    end
  end

  defp server do
    quote do
      use GenServer
      require Logger

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      def join(pid, params \\ %{}) do
        GenServer.call(pid, {:join, params})
      end

      def init(opts) do
        # TODO
        #  Register the channel with the socket
        socket = opts[:socket]
        topic = opts[:topic]
        socket.channel_link(socket, self, topic)
        {:ok, %{
          socket: socket,
          topic: topic,
          sender: nil,
          join_push: nil,
          pushes: [],
          opts: opts
        }}
      end

      def handle_call({:join, params}, from, %{socket: socket} = state) do
        push = socket.push(socket, state.topic, "phx_join", %{})
        {:reply, push, %{state | join_push: push, sender: from}}
      end

      def handle_info({:trigger, "phx_reply", %{"status" => status}, ref} = payload, %{join_push: %{ref: join_ref}} = state) when ref == join_ref do
        handle_reply( {String.to_atom(status), :join, payload, ref}, state)
      end

      def handle_info({:trigger, status, payload, ref}, state) do
        handle_reply({String.to_atom(status), payload, ref}, state)
      end

    end
  end
end
