defmodule Phoenix.Channel.Client.SocketTest do
  use ExUnit.Case, async: false
  use RouterHelper

  import Plug.Conn, except: [assign: 3]

  alias Phoenix.Channel.Client
  alias Phoenix.Channel.Client.Socket
  alias Phoenix.Socket.Message
  alias Phoenix.Socket.Broadcast
  alias __MODULE__.Endpoint

  @port 5807

  Application.put_env(:channel_app, Endpoint, [
    https: false,
    http: [port: @port],
    secret_key_base: String.duplicate("abcdefgh", 8),
    debug_errors: true,
    server: true,
    pubsub: [adapter: Phoenix.PubSub.PG2, name: :int_pub]
  ])

  defmodule RoomChannel do
    use Phoenix.Channel

    def join(topic, message, socket) do
      Process.flag(:trap_exit, true)
      Process.register(self, String.to_atom(topic))
      send(self, {:after_join, message})
      {:ok, socket}
    end

    def handle_info({:after_join, message}, socket) do
      broadcast socket, "user:entered", %{user: message["user"]}
      push socket, "joined", Map.merge(%{status: "connected"}, socket.assigns)
      {:noreply, socket}
    end

    def handle_in("new:msg", message, socket) do
      broadcast! socket, "new:msg", message
      {:noreply, socket}
    end

    def handle_in("boom", _message, _socket) do
      raise "boom"
    end

    def terminate(_reason, socket) do
      push socket, "you:left", %{message: "bye!"}
      :ok
    end
  end

  defmodule Router do
    use Phoenix.Router
  end

  defmodule UserSocket do
    use Phoenix.Socket

    channel "rooms:*", RoomChannel

    transport :longpoll, Phoenix.Transports.LongPoll,
      window_ms: 200,
      origins: ["//example.com"]

    transport :websocket, Phoenix.Transports.WebSocket,
      origins: ["//example.com"]

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
      Logger.disable(self)
      super(conn, opts)
    end

    socket "/ws", UserSocket
    socket "/ws/admin", UserSocket

    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: "*/*",
      json_decoder: Poison

    plug Plug.Session,
      store: :cookie,
      key: "_integration_test",
      encryption_salt: "yadayada",
      signing_salt: "yadayada"

    plug Router
  end

  setup_all do
    capture_log fn -> Endpoint.start_link() end
    :ok
  end

  require Logger

  test "socket can connect to endpoint" do
    {:ok, client} = Client.start_link()
    {:ok, socket} = Client.connect(client, "ws://127.0.0.1:#{@port}/ws/admin/websocket")

    Client.channel(socket, "rooms:admin-lobby", %{})
      |> Client.Channel.on("joined", self)
      |> Client.Channel.join
      |> Client.Push.on_receive("ok", self)

      #|> Client.on_receive("ok", self)
    assert_receive %{payload: %{"status" => "ok"}, topic: "rooms:admin-lobby", event: "phx_reply", ref: _}
    # Client.push("room:lobby", "phx_join", %{})

  end

  # test "endpoint handles mulitple mount segments" do

  #   # {:ok, sock} = Socket.start_link(self, "ws://127.0.0.1:#{@port}/ws/admin/websocket")
  #   # Socket.join(sock, "rooms:admin-lobby", %{})
  #   # assert_receive %Message{event: "phx_reply",
  #   #                         payload: %{"response" => %{}, "status" => "ok"},
  #   #                         ref: "1", topic: "rooms:admin-lobby"}
  # end
end
