# PhoenixChannelClient

Channel client for connecting to Phoenix from Elixir

## Installation

Add phoenix_channel_client as a dependency in your `mix.exs` file.

```elixir
def deps do
  [
    {:phoenix_channel_client, "~> 0.3"},
    {:websocket_client, "~> 1.3"},
    {:jason, "~> 1.0"} #optional. You can use your own JSON serializer
  ]
end
```

## Usage

Phoenix channels require two main components. a `socket` and a `channel`.

### Socket
Using the Phoenix Channel Client requires you add a Socket module to your
supervision tree to handle the socket connection. Start by creating a new
module and have it `use PhoenixChannelClient.Socket`

```elixir
defmodule MyApp.Socket do
  use PhoenixChannelClient.Socket
end
```

You can configure your socket in the Mix config.

```elixir
config :my_app, MyApp.Socket,
  url: "ws://localhost:4000/socket/websocket",
  serializer: Jason,
  params: %{token: "12345"}
```

Then add the socket to your main application supervisor in the application
start callback:

```elixir
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    socket_opts = Application.get_env(:my_app, MyApp.Socket)

    opts = [strategy: :one_for_one, name: Device.Supervisor]
    children = [
      {MyApp.Socket, socket_opts}
    ] ++ children(@target)
    Supervisor.start_link(children, opts)
  end
```

### Channels

Channels function with callbacks inside a defined module.

```elixir
defmodule MyApp.Channel do
  use PhoenixChannelClient

  def handle_in("new_msg", payload, state) do
    {:noreply, state}
  end

  def handle_reply({:ok, "new_msg", resp, _ref}, state) do
    {:noreply, state}
  end
  def handle_reply({:error, "new_msg", resp, _ref}, state) do
    {:noreply, state}
  end
  def handle_reply({:timeout, "new_msg", _ref}, state) do
    {:noreply, state}
  end

  def handle_reply({:timeout, :join, _ref}, state) do
    {:noreply, state}
  end

  def handle_close(reason, state) do
    Process.send_after(self(), :rejoin, 5_000)
    {:noreply, state}
  end
end
```

Channels can then be added to the main supervisor or start_link can be called
at any time. The child spec allows you to pass genserver options to name the
process.

```elixir
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    socket_opts = Application.get_env(:my_app, MyApp.Socket)

    opts = [strategy: :one_for_one, name: Device.Supervisor]
    children = [
      {MyApp.Socket, socket_opts},
      {MyApp.Channel, {[socket: MyApp.Socket, topic: "room:lobby"], [name: MyApp.Channel]}}
    ] ++ children(@target)
    Supervisor.start_link(children, opts)
  end
```

Starting the channel manually:

```elixir
{:ok, socket} = MyApp.Socket.start_link(params: %{token: "12345"})
{:ok, channel} = MyApp.Channel.start_link(socket: socket, topic: "rooms:admin-lobby")
PhoenixChannelClient.join(channel)
PhoenixChannelClient.leave(channel)

push = PhoenixChannelClient.push(channel, "new:message", %{})
PhoenixChannelClient.cancel_push(channel, push)
```
