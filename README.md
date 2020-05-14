# PhoenixClient

Channel client for connecting to Phoenix from Elixir

## Installation

Add `phoenix_client` and a json library as dependencies in your `mix.exs` file.
`jason` is specified as the default json library.

```elixir
def deps do
  [
    {:phoenix_client, "~> 0.3"},
    {:jason, "~> 1.0"}
  ]
end
```

If you choose to use a different json library, you can set it through the
socket options.

## Usage

There are two things required to connect to a phoenix server using channels, a
`PhoenixClient.Socket` and a `PhoenixClient.Channel`. The socket establishes
the connection to the remote socket. The channel takes a topic and is used
to join a remote channel. In the following example we will assume that we are
attempting to communicate with a locally running phoenix server with a `RoomChannel`
with the topic `room:lobby` configured to route to the `RoomChannel`
in the `UserSocket`.

First, Lets create a client socket:

```elixir
socket_opts = [
  url: "ws://localhost:4000/socket/websocket"
]

{:ok, socket} = PhoenixClient.Socket.start_link(socket_opts)
```

The socket will automatically attempt to connect when it starts. If the socket
becomes disconnected, it will attempt to reconnect automatically.

You can control how frequently the socket will attempt to reconnect by setting
`reconnect_interval` in the socket_opts.

Next, we will create a client channel and join the remote.

```elixir
{:ok, _response, channel} = PhoenixClient.Channel.join(socket, "rooms:lobby")
```

Now that we have successfully joined the channel, we are ready to push and receive
new messages. Pushing a message can be done synchronously or asynchronously. If
you require a reply, or want to institute a time out, you can call `push`. If
you do not require a response, you can call `push_async`.

In this example, we will assume the server channel has the following `handle_in`
callbacks:

```elixir
  def handle_in("new:msg", message, socket) do
    {:reply, {:ok, message}, socket}
  end

  def handle_in("new:msg_async", _message, socket) do
    {:noreply, socket}
  end
```

```elixir
message = %{hello: :world}
{:ok, ^message} = PhoenixClient.Channel.push(channel, "new:msg", message)
:ok = PhoenixClient.Channel.push_async(channel, "new:msg_async", message)
```

Messages that are pushed or broadcasted to the client channel will be sent to the
pid that called `join`. Messages will be of the of the struct `%PhoenixClient.Message{}`.

In this example we will assume the server channel has the following `handle_in`
callback

```elixir
  def handle_in("new:msg", message, socket) do
    push(socket, "incoming:msg", message)
    {:reply, :ok, socket}
  end
```

```elixir
message = %{hello: :world}
{:ok, ^message} = PhoenixClient.Channel.push(channel, "new:msg", message)
flush

%PhoenixClient.Message{
  channel_pid: #PID<0.186.0>,
  event: "incoming:msg",
  payload: %{"hello" => "world"},
  ref: nil,
  topic: "room:lobby"
}
```

### Common configuration

You can configure the socket to be started in your main application supervisor.
You will need to name the socket so it can be referenced from your channel.

```elixir
  socket_opts =
    Application.get_env(:phoenix_client, :socket)

  children = [
    {PhoenixClient.Socket, {socket_opts, name: PhoenixClient.Socket}}
  ]
```

You will need a socket for each server you are connecting to. Here is an example
for connecting to multiple remote servers.

```elixir
  socket_1_opts =
    Application.get_env(:phoenix_client, :socket_1)
  socket_2_opts =
    Application.get_env(:phoenix_client, :socket_2)

  children = [
    {PhoenixClient.Socket, {socket_1_opts, name: :socket_1, id: :socket_id_1}},
    {PhoenixClient.Socket, {socket_2_opts, name: :socket_1, id: :socket_id_2}}
  ]
```

Channels are usually constructed in a process such as a `GenServer`. Here is an
example of how this is typically used.

```elixir
defmodule MyApp.Worker do
  use GenServer

  alias PhoenixClient.{Socket, Channel, Message}

  # start_link ...

  def init(_opts) do
    {:ok, _response, channel} = Channel.join(Socket, "room:lobby")
    {:ok, %{
      channel: channel
    }}
  end

  # do some work, call `Channel.push` ...

  def handle_info(%Message{event: "incoming:msg", payload: payload}, state) do
    IO.puts "Incoming Message: #{inspect payload}"
    {:noreply, state}
  end
end
```
