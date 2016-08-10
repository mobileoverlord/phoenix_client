defmodule Phoenix.Channel.Client.Adapters.WebsocketClient do
  @behaviour Phoenix.Channel.Client.Adapter

  require Logger

  def open(url, adapter_opts) do
    :websocket_client.start_link(String.to_char_list(url), __MODULE__, [self(), adapter_opts])
  end

  def close(socket) do
    send socket, :close
  end

  @doc false
  def init([socket, adapter_opts]) do
    {:once, %{sender: socket, keepalive: adapter_opts[:keepalive], json_module: adapter_opts[:json_module]}}
  end

  # def init(opts, conn_state) do
  #   Logger.debug "WS Init"
  #   IO.puts "Opts: #{inspect opts}"
  #   IO.puts "State: #{inspect conn_state}"
  #   {:ok, %{
  #     opts: opts,
  #     json_module: opts[:json_module],
  #     sender: opts[:sender]
  #   }}
  # end

  def onconnect(_req, state) do
    case state.keepalive do
      nil -> {:ok, state}
      keepalive -> {:ok, state, keepalive}
    end
  end

  @doc """
  Receives JSON encoded Socket.Message from remote WS endpoint and
  forwards message to client sender process
  """
  def websocket_handle({:text, msg}, _conn_state, state) do
    #Logger.debug "Handle in: #{inspect msg}"
    send state.sender, {:receive, state.json_module.decode!(msg)}
    {:ok, state}
  end

  @doc """
  Sends JSON encoded Socket.Message to remote WS endpoint
  """
  def websocket_info({:send, msg}, _conn_state, state) do
    #Logger.debug "Handle out: #{inspect json!(msg)}"
    {:reply, {:text, state.json_module.encode!(msg)}, state}
  end

  def websocket_info(:close, _conn_state, state) do
    IO.inspect "Socket Closed"
    send state.sender, {:closed, :normal}
    {:close, <<>>, "done"}
  end

  @doc false
  def ondisconnect(reason, state) do
    IO.inspect "Socket Disconnected"
    send state.sender, {:closed, reason}
    {:close, :normal, state}
  end

  @doc false
  def websocket_terminate(reason, _req, state) do
    send state.sender, {:closed, reason}
    Logger.info(fn -> "Websocket connection closed with reason #{inspect reason}" end)
  end

end
