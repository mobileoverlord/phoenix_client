defmodule PhoenixClientTest do
  use ExUnit.Case, async: false
  use RouterHelper
  import ExUnit.CaptureLog
  import Plug.Conn, except: [assign: 3, push: 3]

  alias __MODULE__.Endpoint
  alias PhoenixClient.{Socket, Channel, Message}

  @port 5807

  Application.put_env(
    :channel_app,
    Endpoint,
    https: false,
    http: [port: @port],
    secret_key_base: String.duplicate("abcdefgh", 8),
    debug_errors: false,
    code_reloader: false,
    server: true,
    pubsub: [adapter: Phoenix.PubSub.PG2, name: :int_pub]
  )

  @socket_config [
    url: "ws://127.0.0.1:#{@port}/ws/admin/websocket",
    serializer: Jason,
    reconnect_interval: 10
  ]

  defmodule RoomChannel do
    use Phoenix.Channel
    require Logger

    def join("rooms:join_timeout", message, socket) do
      :timer.sleep(50)
      {:ok, message, socket}
    end

    def join("rooms:reply", message, socket) do
      {:ok, message, socket}
    end

    def join(topic, message, socket) do
      Process.flag(:trap_exit, true)
      Process.register(self(), String.to_atom(topic))
      send(self(), {:after_join, message})
      {:ok, socket}
    end

    def handle_info({:after_join, message}, socket) do
      broadcast(socket, "user:entered", %{user: message["user"]})
      push(socket, "joined", Map.merge(%{status: "connected"}, socket.assigns))
      {:noreply, socket}
    end

    def handle_info(_, socket) do
      {:noreply, socket}
    end

    def handle_in("new:msg", message, socket) do
      {:reply, {:ok, message}, socket}
    end

    def handle_in("boom", _message, _socket) do
      raise "boom"
    end

    def handle_in(_, _message, socket) do
      {:noreply, socket}
    end

    def terminate(_reason, socket) do
      push(socket, "you:left", %{message: "bye!"})
      :ok
    end
  end

  defmodule Router do
    use Phoenix.Router
  end

  defmodule UserSocket do
    use Phoenix.Socket

    channel("rooms:*", RoomChannel)

    def connect(%{"reject" => "true"}, _socket) do
      :error
    end

    def connect(params, socket) do
      {:ok, assign(socket, :user_id, params["user_id"])}
    end

    def id(socket) do
      if id = socket.assigns.user_id, do: "user_sockets:#{id}"
    end
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :channel_app

    def call(conn, opts) do
      Logger.disable(self())
      super(conn, opts)
    end

    socket("/ws", UserSocket, websocket: [origins: ["//example.com"]])
    socket("/ws/admin", UserSocket, websocket: [origins: ["//example.com"]])

    plug(
      Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: "*/*",
      json_decoder: Jason
    )

    plug(
      Plug.Session,
      store: :cookie,
      key: "_integration_test",
      encryption_salt: "yadayada",
      signing_salt: "yadayada"
    )

    plug(Router)
  end

  defmodule ClientServer do
    use GenServer

    def start(opts \\ []) do
      GenServer.start(__MODULE__, [], opts)
    end

    def push(pid, message) do
      GenServer.cast(pid, {:push, message})
    end

    def messages(pid) do
      GenServer.call(pid, :messages)
    end

    @impl true
    def init(_) do
      state = %{
        socket: nil,
        channel: nil,
        messages: []
      }

      {:ok, state, {:continue, :connect_to_channel}}
    end

    @impl true
    def handle_continue(:connect_to_channel, state) do
      {:ok, socket} = Socket.start_link(PhoenixClientTest.socket_config())
      PhoenixClientTest.wait_for_socket(socket)
      {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")

      {:noreply, %{state | channel: channel, socket: socket}}
    end

    @impl true
    def handle_cast({:push, message}, %{channel: channel} = state) do
      Channel.push_async(channel, "new:msg", message)
      {:noreply, state}
    end

    @impl true
    def handle_call(:messages, _from, %{messages: messages} = state) do
      {:reply, messages, state}
    end

    @impl true
    def handle_info(%Message{payload: payload}, %{messages: messages} = state) do
      {:noreply, %{state | messages: [payload | messages]}}
    end

    @impl true
    def handle_info(_, state) do
      {:noreply, state}
    end
  end

  setup_all do
    start_endpoint()
  end

  require Logger

  test "socket can join a channel" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    assert {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")
  end

  test "socket cannot join more than one channel of the same topic" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    assert {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")
    assert {:error, {:already_joined, ^channel}} = Channel.join(socket, "rooms:admin-lobby")
  end

  test "socket can join a channel and receive a reply" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    message = %{"foo" => "bar"}
    assert {:ok, ^message, _channel} = Channel.join(socket, "rooms:reply", message)
  end

  test "return an error if socket is down" do
    assert {:error, :socket_not_started} = Channel.join(:not_running, "rooms:any")
  end

  test "socket can join a channel with params" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    user_id = "123"
    assert {:ok, _, _} = Channel.join(socket, "rooms:admin-lobby", %{user: user_id})
    assert_receive %Message{event: "user:entered", payload: %{"user" => ^user_id}}
  end

  test "socket can leave a channel" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")
    assert :ok = Channel.leave(channel)
    refute Process.alive?(channel)
  end

  test "client can push to a channel" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")
    assert {:ok, %{"test" => "test"}} = Channel.push(channel, "new:msg", %{test: :test})
  end

  test "join timeouts" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    {:error, :timeout} = Channel.join(socket, "rooms:join_timeout", %{}, 1)
  end

  test "push timeouts" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")

    assert catch_exit(Channel.push(channel, "foo:bar", %{}, 500))
  end

  test "push async" do
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")

    assert :ok = Channel.push_async(channel, "foo:bar", %{})
  end

  test "socket params can be sent" do
    opts =
      @socket_config
      |> Keyword.put(:params, %{"reject" => true})
      |> Keyword.put(:caller, self())

    {:ok, socket} = Socket.start_link(opts)
    :timer.sleep(100)
    refute Socket.connected?(socket)
  end

  test "socket params can be set in url" do
    opts = [
      url: "ws://127.0.0.1:#{@port}/ws/admin/websocket?reject=true",
      serializer: Jason,
      caller: self()
    ]

    {:ok, socket} = Socket.start_link(opts)
    :timer.sleep(100)
    refute Socket.connected?(socket)
  end

  test "rejoin", context do
    endpoint = context[:endpoint]
    {:ok, socket} = Socket.start_link(@socket_config)
    wait_for_socket(socket)
    assert {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")

    Process.exit(endpoint, :kill)
    :timer.sleep(10)

    assert_receive %Message{event: "phx_error"}
    refute Socket.connected?(socket)

    start_endpoint()
    wait_for_socket(socket)
    :sys.get_state(socket)
    assert {:ok, _, channel} = Channel.join(socket, "rooms:admin-lobby")
  end

  test "use async with genserver" do
    {:ok, pid} = ClientServer.start()
    ClientServer.push(pid, %{test: :test})
    assert assert_message(pid, %{"response" => %{"test" => "test"}, "status" => "ok"})
    Process.exit(pid, :kill)
  end

  defp assert_message(pid, message, counter \\ 0)
  defp assert_message(_pid, _message, 10), do: false

  defp assert_message(pid, message, counter) do
    messages = ClientServer.messages(pid)

    if Enum.any?(messages, &(&1 == message)) do
      true
    else
      :timer.sleep(10)
      assert_message(pid, message, counter + 1)
    end
  end

  def wait_for_socket(socket) do
    unless Socket.connected?(socket) do
      wait_for_socket(socket)
    end
  end

  def socket_config(), do: @socket_config

  defp start_endpoint() do
    self = self()

    capture_log(fn ->
      {:ok, pid} = Endpoint.start_link()
      send(self, {:pid, pid})
    end)

    receive do
      {:pid, pid} ->
        Process.unlink(pid)
        [endpoint: pid]
    end
  end
end
