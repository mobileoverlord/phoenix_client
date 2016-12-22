defmodule Phoenix.Channel.Client.Adapters.WebsocketClient do
  @behaviour Phoenix.Channel.Client.Adapter

  require Logger

  def open(url, opts) do
    Logger.debug "Called Open"
    :websocket_client.start_link(String.to_char_list(url), __MODULE__, opts, extra_headers: opts[:headers])
  end

  def close(socket) do
    send socket, :close
  end

  def init(opts, _conn_state) do
    Logger.debug "WS Init"
    {:ok, %{
      opts: opts,
      serializer: opts[:serializer],
      sender: opts[:sender]
    }}
  end

  @doc """
  Receives JSON encoded Socket.Message from remote WS endpoint and
  forwards message to client sender process
  """
  def websocket_handle({:text, msg}, _conn_state, state) do
    #Logger.debug "Handle in: #{inspect msg}"
    send state.sender, {:receive, state.serializer.decode!(msg)}
    {:ok, state}
  end

  @doc """
  Sends JSON encoded Socket.Message to remote WS endpoint
  """
  def websocket_info({:send, msg}, _conn_state, state) do
    #Logger.debug "Handle out: #{inspect json!(msg)}"
    {:reply, {:text, state.serializer.encode!(msg)}, state}
  end

  def websocket_info(:close, _conn_state, state) do
    send state.sender, {:closed, :normal}
    {:close, <<>>, "done"}
  end

  def websocket_terminate(reason, _conn_state, state) do
    send state.sender, {:closed, reason}
    :ok
  end
end
