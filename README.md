# PhoenixChannelClient

Channel client for connecting to Phoenix

## Usage

Add phoenix_channel_client as a dependency in your `mix.exs` file.

```elixir
def deps do
  [
    {:phoenix_channel_client, "~> 0.3"},
    {:jason, "~> 1.0"} #optional. You can use your own JSON serializer
  ]
end
```

Example usage
## Socket
Using the Phoenix Channel Client requires you add a Socket module to your 
supervision tree to handle the socket connection.

```elixir
defmodule MySocket do
  use PhoenixChannelClient.Socket, otp_app: :my_app
end
```

You can configure your socket in the Mix config.

```elixir
config :my_app, MySocket,
  url: "ws://localhost:4000/socket/websocket",
  serializer: Jason,
  params: %{token: "12345"}
```

Channels function with callbacks inside a defined module.

```elixir
defmodule MyChannel do
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
    send_after(5000, :rejoin)
    {:noreply, rejoin(state)}
  end
end
```

General usage:

```elixir
{:ok, socket} = MySocket.start_link(params: %{token: "12345"})
{:ok, channel} = PhoenixChannelClient.channel(MyChannel, socket: MySocket, topic: "rooms:lobby")
MyChannel.join(%{})
MyChannel.leave()

push = MyChannel.push("new:message", %{})
MyChannel.cancel_push(push)
```
