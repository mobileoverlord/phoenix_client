defmodule PhoenixChannelClient.Adapters.WebsocketClient do
  @behaviour PhoenixChannelClient.Adapter

  require Logger

  def open(url, opts) do
    Logger.debug "Called Open"
    :websocket_client.start_link(String.to_charlist(url), __MODULE__, opts, extra_headers: opts[:headers])
  end

  def close(socket) do
    send socket, :close
  end

  def init(opts) do
    Logger.debug "WS Init"
    {:once, %{
      opts: opts,
      serializer: opts[:serializer],
      sender: opts[:sender]
    }}
  end

  def onconnect(_, state) do
    Logger.debug "Websocket Connected"
    send state.sender, {:connected, self()}
    {:ok, state}
  end

  def ondisconnect({:remote, :closed}, state) do
    Logger.debug "Websocket Disconnected"
    send state.sender, {:closed, :normal, self()}
    {:ok, state}
  end

  def ondisconnect({:error, :econnrefused}, state) do
    Logger.debug "Websocket Connection Refused"
    send state.sender, {:closed, :econnrefused, self()}
    {:ok, state}
  end

  def ondisconnect({:error, :nxdomain}, state) do
    Logger.debug "Websocket with non-existent domain"
    send state.sender, {:closed, :nxdomain, self()}
    {:ok, state}
  end

  @doc """
  Receives JSON encoded Socket.Message from remote WS endpoint and
  forwards message to client sender process
  """
  def websocket_handle({:text, msg}, _conn_state, state) do
    Logger.debug "Handle in: #{inspect msg}"
    send state.sender, {:receive, state.serializer.decode!(msg)}
    {:ok, state}
  end

  @doc """
  Sends JSON encoded Socket.Message to remote WS endpoint
  """
  def websocket_info({:send, msg}, conn_state, state) do
    Logger.debug "Handle out: #{inspect msg}"
    Logger.debug "Socket State: #{inspect conn_state}"
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
