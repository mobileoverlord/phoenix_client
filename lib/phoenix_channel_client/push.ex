defmodule Phoenix.Channel.Client.Push do
  use GenServer
  alias Phoenix.Channel.Client.Channel

  def start_link(opts) do
    case GenServer.start_link(__MODULE__, opts) do
      {:ok, pid} -> pid
      {_, error} -> :error
    end
  end

  def on_receive(pid, event, mod) do
    GenServer.call(pid, {:receive, event, mod})
  end

  # def start_timeout(%__MODULE__{agent: agent}) do
  #
  # end

  def init(opts) do
    {:ok, %{
      channel: opts[:channel],
      event: opts[:event],
      payload: %{},
      rec_hooks: [],
      sent: false,
      rev_response: nil,
      after_hook: nil
    }}
  end

  def handle_call({:receive, event, mod}, _from, s) do
    {:reply, self, s}
  end

end
