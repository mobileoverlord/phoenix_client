defmodule PhoenixChannelClientTest do
  use ExUnit.Case, async: false
  use RouterHelper
  import ExUnit.CaptureLog
  import Plug.Conn, except: [assign: 3, push: 3]

  alias __MODULE__.Endpoint
  alias __MODULE__.Socket
  alias PhoenixChannelClient, as: ChannelClient

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
    serializer: Jason
  ]

  defmodule RoomChannel do
    use Phoenix.Channel
    require Logger

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

  defmodule Socket do
    use PhoenixChannelClient.Socket

    def handle_close(reason, %{opts: opts} = state) do
      if caller = Keyword.get(opts, :caller) do
        send(caller, {:socket_closed, reason})
      end
      {:noreply, state}
    end
  end

  defmodule Channel do
    use PhoenixChannelClient
    require Logger

    def handle_in(event, payload, state) do
      if caller = state.opts[:caller] do
        send(caller, {event, payload})
      end
      {:noreply, state}
    end

    # def handle_reply(payload, state) do
    #   send(state.opts[:caller], payload)
    #   {:noreply, state}
    # end

    def handle_close(payload, state) do
      send(state.opts[:caller], {:closed, payload})
      send(self(), :reconnect)
      {:noreply, state}
    end
  end

  require Logger

  setup_all do
    capture_log(fn -> Endpoint.start_link() end)
    :ok
  end

  test "socket can join a channel" do
    {:ok, _} = Socket.start_link(@socket_config)

    assert {:ok, channel} =
      Channel.start_link(socket: Socket, topic: "rooms:admin-lobby")
  end

  test "socket can leave a channel" do
    {:ok, _} = Socket.start_link(@socket_config)

    assert {:ok, channel} =
      Channel.start_link(socket: Socket, topic: "rooms:admin-lobby")

    assert :ok = Channel.stop(channel)
  end

  test "client can push to a channel" do
    {:ok, _} = Socket.start_link(@socket_config)

    {:ok, channel} =
      Channel.start_link(socket: Socket, topic: "rooms:admin-lobby", caller: self())

    assert {:ok, %{"test" => "test"}} = ChannelClient.push(channel, "new:msg", %{test: :test})
  end

  test "push timeouts" do
    {:ok, _} = Socket.start_link(@socket_config)

    {:ok, channel} =
      Channel.start_link(socket: Socket, topic: "rooms:admin-lobby")

    assert catch_exit(ChannelClient.push(channel, "foo:bar", %{}, timeout: 500))
  end

  test "socket params can be sent" do
    opts =
      @socket_config
      |> Keyword.put(:params, %{"reject" => true})
      |> Keyword.put(:caller, self())

    {:ok, _} = Socket.start_link(opts)
    assert_receive {:socket_closed, _reason}
  end
end
