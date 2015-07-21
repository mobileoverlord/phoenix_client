# Phoenix.Channel.Client

Work In Progress!
- [ ] client, channel and push API
- [ ] socket reconnects
- [ ] message buffering
- [ ] test suite

Channel client for connecting to Phoenix

## Usage

Add phoenix_channel_client as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:phoenix_channel_client, "~> 0.0.1"} ]
end
```

Configure the socket
```elixir
config :my_app, Socket,
  url: ws://127.0.0.1:4000/connect

```

Add socket handler
```elixir
defmodule MyApp.Socket do
  use Phoenix.Channel.Client.Socket, opt_app: :my_app

end
```

You can either start the socket by adding it to the application supervisor...
```elixir
worker(MyApp.Socket, [])
```

or by calling it directly
```elixir
  MyApp.Socket.start_link()
```

Add a channel handler and use the socket in the channel config
```elixir
defmodule MyApp.Channel do
  use Phoenix.Channel.Client.Channel

  # Phoenix Handlers

  def phoenix_handle({:event, "new_message"}, payload, state) do
    # The channel received an event message
  end

  def phoenix_handle({:receive, "ok", %Push{}}, payload, state) do
    # The push received a response
  end

  def phoenix_handle({:timeout, milliseconds, %Push{}}, payload, state) do
    # The push timeout was called
  end

  def phoenix_handle({:close}, payload, state) do
    # Channel communication closed
  end

  def phoenix_handle({:error}, payload, state) do
    # Channel communication error
  end
end
```

You can then make calls to join channels and push messages. With this setup, callbacks to events / pushes will appear at the channel module.
```elixir
MyApp.Channel.join("my:topic", %{foo: :bar}, socket: MyApp.Socket, timeout: 5000)
MyApp.Channel.push("new:message", %{param: 1}, timeout: 5000)
```
