defmodule PhoenixClient.Transports.Websocket do
  @behaviour PhoenixClient.Transport

  require Logger

  def open(url, transport_opts) do
    :websocket_client.start_link(
      String.to_charlist(url),
      __MODULE__,
      transport_opts,
      transport_opts
    )
  end

  def close(socket) do
    send(socket, :close)
  end

  def init(opts) do
    {:once,
     %{
       opts: opts,
       sender: opts[:sender]
     }}
  end

  def onconnect(_, state) do
    send(state.sender, {:connected, self()})
    {:ok, state}
  end

  def ondisconnect(reason, state) do
    send(state.sender, {:disconnected, reason, self()})
    {:close, :normal, state}
  end

  @doc """
  Receives JSON encoded Socket.Message from remote WS endpoint and
  forwards message to client sender process
  """
  def websocket_handle({:text, msg}, _conn_state, state) do
    send(state.sender, {:receive, msg})
    {:ok, state}
  end

  def websocket_handle({:pong, _msg}, _conn_state, state) do
    # Ignore pong responses when :websocket_client is configured to send
    # keepalive messages.
    {:ok, state}
  end

  def websocket_handle(other_msg, _req, state) do
    Logger.warn(fn -> "Unknown message #{inspect(other_msg)}" end)
    {:ok, state}
  end

  @doc """
  Sends JSON encoded Socket.Message to remote WS endpoint
  """
  def websocket_info({:send, msg}, _conn_state, state) do
    {:reply, {:text, msg}, state}
  end

  def websocket_info(:close, _conn_state, state) do
    send(state.sender, {:closed, :normal, self()})
    {:close, <<>>, "done"}
  end

  def websocket_info(_message, _req, state) do
    {:ok, state}
  end

  def websocket_terminate(_reason, _conn_state, _state) do
    :ok
  end
end
