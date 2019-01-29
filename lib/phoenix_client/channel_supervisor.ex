defmodule PhoenixClient.ChannelSupervisor do
  use DynamicSupervisor

  alias PhoenixClient.Channel

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_channel(socket, topic, params) do
    spec = Channel.child_spec({socket, topic, params})
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
