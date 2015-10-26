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

      @default_timeout 5_000

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      def join(pid, params \\ %{}) do
        GenServer.call(pid, {:join, params})
      end

      def cancel_push(pid, push_ref) do
        GenServer.call(pid, {:cancel_push, push_ref})
      end

      def push(pid, event, payload, opts \\ []) do
        timeout =  opts[:timeout] || @default_timeout
        GenServer.call(pid, {:push, event, payload, timeout})
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

      def handle_info({:trigger, "phx_reply", %{"status" => status}, ref} = payload, %{join_push: %{ref: join_ref}} = state) when ref == join_ref do
        handle_reply( {String.to_atom(status), :join, payload, ref}, state)
      end

      def handle_info({:trigger, event, payload, ref} = p, state) do
        #Logger.debug "Trigger: #{inspect p}"
        handle_in(event, payload, state)
      end

      # Push timer expired
      def handle_info({:timeout, timer, push}, %{pushes: pushes} = state) do
        {[{_, push}], pushes} = Enum.partition(pushes, fn({ref, _}) ->
          ref == timer
        end)

        handle_reply({:timeout, push.event, push.ref}, %{state | pushes: pushes})
      end
    end
  end
end
