defmodule Phoenix.Channel.Client.Server do
  @callback handle_in(event :: String.t, payload :: map, state :: map) :: {:noreply, state :: map}

  defmacro __using__(_opts) do
    quote do
      @behaviour Phoenix.Channel.Client.Server
      unquote(server)
    end
  end

  defp server do
    quote location: :keep do
      use GenServer
      require Logger

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)
      end

      def join(pid, params \\ %{}) do
        GenServer.cast(pid, {:join, params})
      end

      def init(opts) do
        # TODO
        #  Register the channel with the socket
        Logger.debug "Channel PID: #{inspect self}"
        socket = opts[:socket]
        topic = opts[:topic]
        socket.channel_link(socket, self, topic)
        {:ok, %{
          socket: socket,
          topic: topic,
          pushes: []
        }}
      end

      def handle_cast({:join, params}, %{socket: socket} = state) do
        socket.push(socket, state.topic, "phx_join", %{})
        {:noreply, state}
      end

      # def handle_info({:trigger, "phx_reply", payload, ref}, state) do
      #   Logger.debug "Handle Reply: #{inspect ref}"
      #   {:noreply, state}
      # end
      #
      # def handle_info({:trigger, event, payload, ref}, state) do
      #   Logger.debug "Handle In: #{inspect event}"
      #   {:noreply, state}
      # end

    end
  end
end

# defmodule Phoenix.Channel.Client.Channel do
#   use GenServer
#
#   defstruct pid: nil, socket: nil, topic: "", params: %{}
#
#   alias Phoenix.Channel.Client.Socket
#   alias Phoenix.Channel.Client.Push
#
#   require Logger
#
#   @timeout 5000
#   @push_timeout 30_000
#   @event_reply :phx_reply
#
#   def start_link(opts) do
#     case GenServer.start_link(__MODULE__, opts) do
#       {:ok, pid} -> %__MODULE__{pid: pid, socket: opts[:socket], topic: opts[:topic], params: opts[:params]}
#       err -> err
#     end
#   end
#
#   def join(pid, mod \\ nil, params \\ %{}) do
#     case GenServer.call(pid, {:join, mod, params}) do
#       %Push{} = push -> push
#       error -> {:error, error}
#     end
#   end
#
#   def leave(pid, params) do
#     GenServer.call(pid, {:leave, params})
#   end
#
#
#   # def put(%Push{channel: pid} = push) do
#   #   GenServer.call(pid, {:put, push})
#   # end
#
#   def on(pid, event, mod) do
#     Logger.debug "Pid: #{inspect pid}"
#     GenServer.call(pid, {:on_event, event, mod})
#   end
#
#   def push(pid, event, payload) do
#     GenServer.call(pid, {:push, event, payload})
#   end
#
#   # def on(%Push{channel: pid} = push, event, func) do
#   #   GenServer.call(pid, {:receive, push, event, func})
#   # end
#
#   def trigger(pid, event, payload, ref) do
#     GenServer.cast(pid, {:trigger, event, payload, ref})
#   end
#
#   def init(opts) do
#     {:ok, %{
#       state: :closed,
#       socket: opts[:socket],
#       topic: opts[:topic],
#       params: opts[:params],
#       joined_once: false,
#       bindings: [],
#       join_push: nil,
#       pushes: [],
#       rejoin_timer_ref: nil,
#       buffer: []
#     }}
#   end
#
#   # TODO: Need to pass mod to Push and store for result.
#   def handle_call({:join, _mod, params}, _from, %{socket: socket} = s) do
#     Logger.debug "Channel Join: #{inspect s.topic}, #{inspect params}"
#     push = Push.start_link(channel: self, event: "phx_join")
#     Socket.push(socket.pid, s.topic, push)
#     {:reply, push, %{s | join_push: push}}
#   end
#
#   def handle_call({:leave, params}, _from, %{socket: socket} = s) do
#     Socket.push(socket.pid, s.topic, %Push{channel: self, event: "phx_leave", payload: params})
#     {:stop, s}
#   end
#
#   def handle_call({:on_event, event, mod}, _from, %{bindings: bindings} = s) do
#     Logger.debug "Registered On: #{inspect mod}"
#     {:reply, self, %{s | bindings: [{event, mod} | bindings]}}
#   end
#
#   # def handle_call({:put, %Push{} = push}, _from, %{pushes: pushes} = s) do
#   #   Logger.debug "Put Push"
#   #   pushes = pushes
#   #     |> Enum.reject(&(&1 == push))
#   #   {:reply, push, %{s | pushes: [push | pushes]}}
#   # end
#
#   def handle_call({:push, event, payload}, _from, s) do
#
#   end
#
#   def handle_call({:after, %Push{} = push, event, func}, _from, %{pushes: pushes} = s) do
#     push = Push.on_after push, event, func
#     pushes = pushes
#       |> Enum.reject(&(&1 == push))
#     {:reply, push, %{s | pushes: [push | pushes]}}
#   end
#
#   def handle_cast({:trigger, @event_reply, payload, ref}, s) do
#     Logger.debug "Trigger Reply"
#     trigger_event(@event_reply, payload, reply_event_name(ref), s)
#     {:noreply, s}
#   end
#
#   def handle_cast({:trigger, event, payload, ref}, s) do
#     trigger_event(event, payload, ref, s)
#     {:noreply, s}
#   end
#
#   defp trigger_event(event, payload, ref, %{bindings: bindings, topic: topic}) do
#     Logger.debug "Trigger Event"
#     Enum.filter(bindings, fn({event, _mod}) -> event == event end)
#       |> Enum.each(fn({event, mod}) -> send(mod, %{payload: payload, event: event, topic: topic, ref: ref}) end)
#   end
#
#   defp reply_event_name(ref), do: "chan_reply_#{ref}"
# end
