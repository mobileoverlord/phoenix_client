defmodule Phoenix.Channel.Client.Socket do
  alias Poison, as: JSON

  require Logger

  def start_link(sender, url, headers \\ []) do
    :crypto.start
    :ssl.start
    :websocket_client.start_link(String.to_char_list(url), __MODULE__, [sender],
                                 extra_headers: headers)
  end

  def channel(socket, topic, params \\ %{}) do
    Channel.start_link()
  end

  def init([sender], _conn_state) do
    {:ok, %{sender: sender, ref: 0}}
  end

  def close(socket) do
    send(socket, :close)
  end

  @doc """
  Receives JSON encoded Socket.Message from remote WS endpoint and
  forwards message to client sender process
  """
  def websocket_handle({:text, msg}, _conn_state, state) do
    Logger.debug "Recv: #{inspect msg}"
    Logger.debug "Sender: #{inspect state.sender}"
    send state.sender, JSON.decode!(msg)
    {:ok, state}
  end

  @doc """
  Sends JSON encoded Socket.Message to remote WS endpoint
  """
  def websocket_info({:send, msg}, _conn_state, state) do
    msg = Map.put(msg, :ref, to_string(state.ref + 1))
    Logger.debug "Send Message: #{inspect msg}"
    {:reply, {:text, json!(msg)}, put_in(state, [:ref], state.ref + 1)}
  end

  def websocket_info(:close, _conn_state, _state) do
    {:close, <<>>, "done"}
  end

  def websocket_terminate(_reason, _conn_state, _state) do
    :ok
  end

  @doc """
  Sends an event to the WebSocket server per the Message protocol
  """
  def push(socket_pid, topic, event, msg) do
    Logger.debug "Socket Push: #{inspect topic}, #{inspect event}, #{inspect msg}"
    send socket_pid, {:send, %{topic: topic, event: event, payload: msg}}
  end

  defp json!(map), do: JSON.encode!(map)
end
