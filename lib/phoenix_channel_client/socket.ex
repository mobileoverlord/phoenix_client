defmodule Phoenix.Channel.Client.Socket do
  require Logger
  alias Poison, as: JSON
  alias Phoenix.Channel.Client.Push

  defstruct pid: nil, client: nil

  def start_link(opts) do
    headers = opts[:headers] || []
    :crypto.start
    :ssl.start
    {:ok, pid} = :websocket_client.start_link(String.to_char_list(opts[:url]), Phoenix.Channel.Client.Socket, opts,
                             extra_headers: headers)
    %__MODULE__{pid: pid}
  end

  # def channel(socket, topic, params \\ %{}) do
  #   Channel.start_link()
  # end

  def close(socket) do
    send(socket, :close)
  end

  def init(opts, _conn_state) do
    {:ok, %{
      sender: opts[:sender],
      ref: 0
    }}
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
  def push(socket_pid, topic, %Push{event: event, payload: payload}) do
    Logger.debug "Socket Push: #{inspect topic}, #{inspect event}, #{inspect payload}"
    send socket_pid, {:send, %{topic: topic, event: event, payload: payload}}
  end

  defp json!(map), do: JSON.encode!(map)
end
