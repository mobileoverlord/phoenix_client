# Phoenix.Channel.Client

Work In Progress!
- [x] client, channel and push API
- [ ] socket reconnects
- [ ] message buffering

Channel client for connecting to Phoenix

## Usage

Add phoenix_channel_client as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:phoenix_channel_client, "~> 0.0.1"} ]
end
```

Example usage
## Socket
Using the Phoenix Channel Client requires you add a Socket module to your supervision tree for handling the socket connection.
```elixir
defmodule MySocket do
  use Phoenix.Channel.Client.Socket, otp_app: :my_app
end
```

```elixir
config :my_app, MySocket,
  url: "ws://localhost:4000/socket/websocket"
```

Channels function with callbacks inside a module
```elixir
defmodule MyChannel do
  use Phoenix.Channel.Client.Server

  def handle_in("new_msg", payload, state) do
    {:noreply, state}
  end  

  def handle_reply({:ok, "new_msg", resp, _ref}, state) do
    {:noreply, state}
  end
  def handle_reply({:error, "new_msg", resp, _ref} state) do
    {:noreply, state}
  end
  def handle_reply({:timeout, "new_msg", _ref} state) do
    {:noreply, state}
  end

  def handle_reply({:timeout, :join, _ref} state) do
    {:noreply, state}
  end

  def handle_close(reason, state) do
    send_after(5000, :rejoin)
    {:noreply, rejoin(state)}
  end
end
```

usage
```elixir
{:ok, socket} = MySocket.start_link
MyChannel.start_link(socket: MySocket, topic: "rooms:lobby")
MyChannel.join(%{})
MyChannel.leave()

push = MyChannel.push("new:message", %{})
MyChannel.cancel_push(push)
```
