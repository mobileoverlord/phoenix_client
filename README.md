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
Example usage
```elixir
alias Phoenix.Channel.Client
{:ok, client} = Client.start_link
{:ok, socket} = Client.connect client, %{user_id: token}

Client.channel(socket, "rooms:lobby", %{})
|> Client.Channel.on_event("new:message", self)
|> Client.Channel.join
|> Push.on_receive("ok", self)
|> Push.on_receive("timeout", self)

Client.push(channel, "new:message", %{})
```
