defmodule PhoenixClient.Channel do
  use GenServer

  alias PhoenixClient.{Socket, ChannelSupervisor, Message}

  @timeout 5_000
  @first_join_ms 0
  @backoff_buckets [1_000, 2_000, 5_000]
  @max_backoff 10_000

  @type t :: %__MODULE__{
          caller: pid | nil,
          socket: pid,
          topic: String.t() | atom,
          params: map,
          options: keyword,
          pushes: [{pid, Message.t()}],
          join_ref: String.t() | nil,
          joined: boolean,
          rejoin_ref: reference | nil,
          tries: non_neg_integer
        }

  defstruct [
    :caller,
    :socket,
    :topic,
    :join_ref,
    :rejoin_ref,
    params: %{},
    options: [],
    pushes: [],
    joined: false,
    tries: 0
  ]

  def child_spec({socket, topic, params, opts}) do
    %{
      id: Module.concat(__MODULE__, topic),
      start: {__MODULE__, :start_link, [socket, topic, params, opts]},
      restart: :temporary
    }
  end

  @doc false
  def start_link(socket, topic, params, opts) do
    GenServer.start_link(__MODULE__, {socket, topic, params, opts})
  end

  @doc false
  def stop(pid) do
    leave(pid)
  end

  @doc """
  Join a channel topic through a socket with optional params

  A socket can only join a topic once. If the socket you pass already has a
  channel connection for the supplied topic, you will receive an error
  `{:error, {:already_joined, pid}}` with the channel pid of the process joined
  to that topic through that socket. If you require to join the same topic with
  multiple processes, you will need to start a new socket process for each channel.

  Calling join will link the caller to the channel process.

  Optional parameters is a keyword list with the following options:
  - `first_join_ms: non_neg_integer` -> First timeout when sending the join message since the process starts. Default `0`
  - `backoff_buckets: [non_neg_integer]` -> List of timeouts to be applied on the different backoff retries. Default [1_000, 2_000, 5_000]
  - `max_backoff: non_neg_integer` -> Maximum timeout to be applied on the backoff algorithm, if the retry doesn't fit on any bucket, it will use this timeout.
  """
  @spec join(pid | atom, binary, map, keyword) ::
          {:ok, pid}
          | {:error, :socket_not_connected}
          | {:error, any}
  def join(socket_pid_or_name, topic, params \\ %{}, opts \\ [])
  def join(nil, _topic, _params, _opts), do: {:error, :socket_not_started}

  def join(socket_name, topic, params, opts) when is_atom(socket_name) do
    join(Process.whereis(socket_name), topic, params, opts)
  end

  def join(socket_pid, topic, params, opts) do
    with {:socket, true} <- {:socket, Process.alive?(socket_pid)},
         {:ok, pid} <- ChannelSupervisor.start_channel(socket_pid, topic, params, opts),
         :ok <- set_parent(pid) do
      Process.link(pid)

      {:ok, pid}
    else
      {:socket, _} -> {:error, :socket_not_connected}
      error -> error
    end
  end

  @doc """
  Leave the channel topic and stop the channel
  """
  @spec leave(pid) :: :ok
  def leave(pid) do
    GenServer.call(pid, :leave)
  end

  @doc """
  Push a message to the server and wait for a response or timeout

  The server must be configured to return `{:reply, _, socket}`
  otherwise, the call will timeout.
  """
  @spec push(pid, binary, map, non_neg_integer) :: term()
  def push(pid, event, payload, timeout \\ @timeout) do
    GenServer.call(pid, {:push, event, payload}, timeout)
  end

  @doc """
  Push a message to the server and do not wait for a response
  """
  @spec push_async(pid, binary, map) :: :ok
  def push_async(pid, event, payload) do
    GenServer.cast(pid, {:push, event, payload})
  end

  @doc """
  Check if the channel is joined or not
  """
  @spec joined?(pid) :: boolean
  def joined?(pid) do
    GenServer.call(pid, :joined?)
  end

  # Callbacks
  @impl true
  def init({socket, topic, params, opts}) do
    case Socket.channel_join(socket, self(), topic) do
      :ok ->
        Process.link(socket)
        Process.flag(:trap_exit, true)

        first_join = Keyword.get(opts, :first_join_ms, @first_join_ms)
        Process.send_after(self(), :join, first_join)

        state = %__MODULE__{
          socket: socket,
          topic: topic,
          params: params,
          options: opts
        }

        {:ok, state}

      {:error, error} ->
        {:stop, error}

      error ->
        {:stop, error}
    end
  end

  @impl true
  def handle_call(:set_parent, {pid, _ref}, state) do
    state = %{state | caller: pid}
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:joined?, _from, %{joined: joined} = state) do
    {:reply, joined, state}
  end

  @impl true
  def handle_call(:leave, _from, %{socket: socket, topic: topic} = state) do
    send_leave(socket, topic)
    Socket.channel_leave(socket, self(), topic)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call({:push, event, payload}, from, %{socket: socket, topic: topic} = state) do
    push =
      Socket.push(socket, %Message{
        topic: topic,
        event: event,
        payload: payload,
        join_ref: state.join_ref
      })

    {:noreply, %{state | pushes: [{from, push} | state.pushes]}}
  end

  @impl true
  def handle_cast({:push, event, payload}, %{socket: socket, topic: topic} = state) do
    message = %Message{
      topic: topic,
      event: event,
      payload: payload,
      channel_pid: self(),
      join_ref: state.join_ref
    }

    Socket.push(socket, message)
    {:noreply, state}
  end

  @impl true
  def handle_info(:join, %{joined: false} = state) do
    state = do_join(state)

    {:noreply, state}
  end

  @impl true
  def handle_info(:join, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{event: "phx_reply", ref: ref, join_ref: ref} = msg, state) do
    send_message(msg, state)

    state = check_join_response(msg, state)
    {:noreply, state}
  end

  def handle_info(%Message{event: "phx_reply", ref: ref} = msg, %{pushes: pushes} = s) do
    pushes =
      case Enum.split_with(pushes, &(elem(&1, 1).ref == ref)) do
        {[{from_ref, _push}], pushes} ->
          %{"status" => status, "response" => response} = msg.payload
          GenServer.reply(from_ref, {String.to_atom(status), response})
          pushes

        {_, pushes} ->
          send(s.caller, %{msg | channel_pid: s.caller, topic: s.topic})
          pushes
      end

    {:noreply, %{s | pushes: pushes}}
  end

  @impl true
  def handle_info(%Message{event: "phx_close"} = message, state) do
    send_message(message, state)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(%Message{event: "phx_error"} = message, state) do
    send_message(message, state)

    state = rejoin(%{state | joined: false})
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{} = message, state) do
    send_message(message, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    cond do
      pid == state.socket -> {:stop, reason, state}
      pid == state.caller -> {:stop, reason, state}
      true -> {:noreply, state}
    end
  end

  defp set_parent(channel_pid) do
    GenServer.call(channel_pid, :set_parent)
  end

  defp do_join(%{socket: socket, topic: topic, params: params} = state) do
    state |> socket_send_join(socket, topic, params) |> rejoin()
  end

  defp socket_send_join(state, socket, topic, params) do
    case Socket.connected?(socket) do
      true ->
        push = send_join(socket, topic, params)
        %{state | join_ref: push.ref}

      _ ->
        state
    end
  end

  defp check_join_response(%{payload: %{"status" => "ok"}}, state) do
    cancel_rejoin(state)
    %{state | joined: true, rejoin_ref: nil, tries: 0}
  end

  defp check_join_response(_msg, state) do
    rejoin(state)
  end

  defp send_join(socket, topic, params) do
    message = Message.join(topic, params)
    Socket.push(socket, message)
  end

  defp send_leave(socket, topic) do
    message = Message.leave(topic)
    Socket.push(socket, message)
  end

  defp rejoin(state) do
    cancel_rejoin(state)

    backoff_ms = backoff(state)
    rejoin_ref = Process.send_after(self(), :join, backoff_ms)

    %{state | rejoin_ref: rejoin_ref, tries: state.tries + 1}
  end

  defp cancel_rejoin(%{rejoin_ref: ref}) when is_reference(ref) do
    Process.cancel_timer(ref)
  end

  defp cancel_rejoin(_), do: :ok

  defp backoff(%{tries: tries, options: opts}), do: backoff(tries, opts)

  defp backoff(tries, opts) do
    buckets = Keyword.get(opts, :backoff_buckets, @backoff_buckets)

    case Enum.at(buckets, tries) do
      nil -> Keyword.get(opts, :max_backoff, @max_backoff)
      timeout -> timeout
    end
  end

  defp send_message(message, %{caller: pid, topic: topic}) do
    send(pid, %{message | channel_pid: pid, topic: topic})
  end
end
