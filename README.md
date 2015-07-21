# Phoenix.Channel.Client

Channel client for connecting to Phoenix

## Usage

Add phoenix_channel_client as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:phoenix_channel_client, "~> 0.0.1"} ]
end
```

```elixir
alias Phoenix.Channel.Client

{:ok, client} = Client.start_link
{:ok, _socket} = Client.connect client, "ws://127.0.0.1:4000/connect"
{:ok, channel} = Client.channel client, "device:lobby"

Client.Channel.on(channel, "new_msg", fn(payload) ->
  # Do Something
end)

Client.Channel.join(channel, %{foo: :bar})
  |> on_receive("ok", fn() -> IO.puts("Ok") end)
  |> on_after(5000, fn() -> IO.puts("After") end)


Client.Channel.push(channel, "new:message", %{param: 1})

```
