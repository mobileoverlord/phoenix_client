defmodule PhoenixChannelClient.Adapters.WebsocketClient do
  @behaviour PhoenixChannelClient.Adapter

  require Logger

  def open(url, adapter_opts) do
    :websocket_client.start_link(String.to_charlist(url), __MODULE__, adapter_opts, adapter_opts)
  end

  def close(socket) do
    send socket, :close
  end

  def init(opts) do
    {:once, %{
      opts: opts,
      serializer: opts[:serializer],
      sender: opts[:sender]
    }}
  end

  def onconnect(_, state) do
    send state.sender, {:connected, self()}
    {:ok, state}
  end

  def ondisconnect({:remote, :closed}, state) do
    send state.sender, {:closed, :normal, self()}
    {:ok, state}
  end

  def ondisconnect({:error, reason}, state) do
    send state.sender, {:closed, reason, self()}
    {:ok, state}
  end

  @doc """
  Receives JSON encoded Socket.Message from remote WS endpoint and
  forwards message to client sender process
  """
  def websocket_handle({:text, msg}, _conn_state, state) do
    send state.sender, {:receive, state.serializer.decode!(msg)}
    {:ok, state}
  end

  @doc """
  Sends JSON encoded Socket.Message to remote WS endpoint
  """
  def websocket_info({:send, msg}, conn_state, state) do
    {:reply, {:text, state.serializer.encode!(msg)}, state}
  end

  def websocket_info(:close, _conn_state, state) do
    send state.sender, {:closed, :normal, self()}
    {:close, <<>>, "done"}
  end

  def websocket_terminate(reason, _conn_state, state) do
    send state.sender, {:closed, reason, self()}
    :ok
  end
end
