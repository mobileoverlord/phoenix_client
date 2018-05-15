defmodule PhoenixChannelClientTest do
  use ExUnit.Case, async: false
  use RouterHelper
  import ExUnit.CaptureLog
  import Plug.Conn, except: [assign: 3, push: 3]

  alias __MODULE__.Endpoint
  alias __MODULE__.ClientSocket

  @port 5807

  Application.put_env(:channel_app, Endpoint, [
    https: false,
    http: [port: @port],
    secret_key_base: String.duplicate("abcdefgh", 8),
    debug_errors: true,
    server: true,
    pubsub: [adapter: Phoenix.PubSub.PG2, name: :int_pub]
  ])

  @socket_config [
    url: "ws://127.0.0.1:#{@port}/ws/admin/websocket",
    serializer: Jason
  ]

  defmodule RoomChannel do
    use Phoenix.Channel
    require Logger
    def join(topic, message, socket) do
      Logger.debug "Channel Join Called"
      Process.flag(:trap_exit, true)
      Process.register(self(), String.to_atom(topic))
      send(self(), {:after_join, message})
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

    def handle_in(_, _message, socket) do
      {:noreply, socket}
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
      IO.inspect "rejected"
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

    socket "/ws", UserSocket
    socket "/ws/admin", UserSocket

    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: "*/*",
      json_decoder: Jason

    plug Plug.Session,
      store: :cookie,
      key: "_integration_test",
      encryption_salt: "yadayada",
      signing_salt: "yadayada"

    plug Router
  end

  defmodule ClientSocket do
    use PhoenixChannelClient.Socket

    def handle_close(reason, state) do
      send(state.opts[:caller], {:socket_closed, reason})
      {:noreply, state}
    end
  end

  defmodule ClientChannel do
    use PhoenixChannelClient
    require Logger

    def handle_in(event, payload, state) do
      send(state.opts[:caller], {event, payload})
      {:noreply, state}
    end

    def handle_reply(payload, state) do
      send(state.opts[:caller], payload)
      {:noreply, state}
    end

    def handle_close(payload, state) do
      send(state.opts[:caller], {:closed, payload})
      {:noreply, state}
    end
  end

  require Logger

  setup_all do
    #Endpoint.start_link()
    capture_log fn -> Endpoint.start_link() end
    :ok
  end

  test "socket can join a channel" do
    {:ok, _} = ClientSocket.start_link(@socket_config)
    {:ok, _channel} = ClientChannel.start_link(socket: ClientSocket, topic: "rooms:admin-lobby", caller: self())
    %{ref: ref} = ClientChannel.join
    assert_receive {:ok, :join, _, ^ref}
  end

  test "socket can leave a channel" do
    {:ok, _} = ClientSocket.start_link(@socket_config)
    {:ok, _channel} = ClientChannel.start_link(socket: ClientSocket, topic: "rooms:admin-lobby", caller: self())
    %{ref: ref} = ClientChannel.join
    assert_receive {:ok, :join, _, ^ref}
    ClientChannel.leave
    assert_receive {"you:left", %{"message" => "bye!"}}
    assert_receive {:closed, _}
  end

  test "client can push to a channel" do
    {:ok, _} = ClientSocket.start_link(@socket_config)
    {:ok, _channel} = ClientChannel.start_link(socket: ClientSocket, topic: "rooms:admin-lobby", caller: self())
    %{ref: ref} = ClientChannel.join
    assert_receive {:ok, :join, _, ^ref}
    ClientChannel.push("new:msg", %{test: :test})
    assert_receive {"new:msg", %{"test" => "test"}}
  end

  test "push timeouts are received" do
    {:ok, _} = ClientSocket.start_link(@socket_config)
    {:ok, _channel} = ClientChannel.start_link(socket: ClientSocket, topic: "rooms:admin-lobby", caller: self())
    %{ref: ref} = ClientChannel.join
    assert_receive {:ok, :join, _, ^ref}
    %{ref: ref} = ClientChannel.push("foo:bar", %{}, timeout: 500)
    :timer.sleep(1_000)
    assert_receive {:timeout, "foo:bar", ^ref}
  end

  test "push timeouts are able to be canceled" do
    {:ok, _} = ClientSocket.start_link(@socket_config)
    {:ok, _channel} = ClientChannel.start_link(socket: ClientSocket, topic: "rooms:admin-lobby", caller: self())
    %{ref: ref} = ClientChannel.join
    assert_receive {:ok, :join, _, ^ref}
    %{ref: ref} = ClientChannel.push("foo:bar", %{}, timeout: 100)
    ClientChannel.cancel_push(ref)
    refute_receive {:timeout, "foo:bar", ^ref}, 200
  end

  test "socket params can be sent" do
    opts = 
      @socket_config
      |> Keyword.put(:params, %{"reject" => true})
      |> Keyword.put(:caller, self())

    {:ok, _} = ClientSocket.start_link(opts)
    assert_receive {:socket_closed, _reason}
  end


end
