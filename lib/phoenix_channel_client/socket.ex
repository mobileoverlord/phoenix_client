defmodule Phoenix.Channel.Client.Socket do

  use Behaviour
  require Logger
  defcallback websocket_handle({event :: atom, msg :: binary}, any, state :: map)

  defmacro __using__(_) do
    IO.inspect __MODULE__
    quote do
      @behaviour Phoenix.Channel.Client.Socket
      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :phoenix_channels, accumulate: true)
      @before_compile unquote(__MODULE__)

      unquote(server)
    end
  end

  defmacro __before_compile__(env) do
    channel_defs =
      env.module
      |> Module.get_attribute(:phoenix_channels)
      |> defchannels

    quote do
      unquote(channel_defs)
    end
  end

  defmacro channel(topic, module, opts \\ []) do
    quote do
      @phoenix_channels {
        unquote(topic),
        unquote(module)
      }
    end
  end

  defp defchannels(channels) do
    channels_ast = for {topic_pattern, module, opts} <- channels do
      defchannel(topic_pattern, module)
    end
  end

  defp defchannel(topic_match, channel_module) do
    quote do
      def channel_for_topic(unquote(topic_match)) do
        unquote(channel_module)
      end
    end
  end

  defp server() do
    quote location: :keep, unquote: false do
      alias Poison, as: JSON

      def start_link(opts) do
        headers = opts[:headers] || []
        :crypto.start
        :ssl.start
        :websocket_client.start_link(String.to_char_list(opts[:url]), unquote(__MODULE__), [],
                                 extra_headers: headers)
      end

      def init([], _conn_state) do
        {:ok, %{ref: 0}}
      end

      def websocket_handle({:text, msg}, _conn_state, state) do
        {:ok, state}
      end

      def websocket_info({:send, msg}, _conn_state, state) do
        msg = Map.put(msg, :ref, to_string(state.ref + 1))
        {:reply, {:text, json!(msg)}, put_in(state, [:ref], state.ref + 1)}
      end

      def websocket_info(:close, _conn_state, _state) do
        {:close, <<>>, "done"}
      end

      def websocket_terminate(_reason, _conn_state, _state) do
        :ok
      end

      defp json!(map), do: JSON.encode!(map)
    end
  end




  # def start_link(opts) do
  #   headers = opts[:headers] || []
  #   :crypto.start
  #   :ssl.start
  #   :websocket_client.start_link(String.to_char_list(opts[:url]), Phoenix.Channel.Client.Socket, [opts[:sender]],
  #                            extra_headers: headers)
  # end

  # def channel(socket, topic, params \\ %{}) do
  #   Channel.start_link()
  # end

  # def close(socket) do
  #   send(socket, :close)
  # end

  # def init([sender], _conn_state) do
  #   {:ok, %{sender: sender, ref: 0}}
  # end

  # @doc """
  # Receives JSON encoded Socket.Message from remote WS endpoint and
  # forwards message to client sender process
  # """
  # def websocket_handle({:text, msg}, _conn_state, state) do
  #   Logger.debug "Recv: #{inspect msg}"
  #   Logger.debug "Sender: #{inspect state.sender}"
  #   send state.sender, JSON.decode!(msg)
  #   {:ok, state}
  # end

  # @doc """
  # Sends JSON encoded Socket.Message to remote WS endpoint
  # """
  # def websocket_info({:send, msg}, _conn_state, state) do
  #   msg = Map.put(msg, :ref, to_string(state.ref + 1))
  #   Logger.debug "Send Message: #{inspect msg}"
  #   {:reply, {:text, json!(msg)}, put_in(state, [:ref], state.ref + 1)}
  # end

  # def websocket_info(:close, _conn_state, _state) do
  #   {:close, <<>>, "done"}
  # end

  # def websocket_terminate(_reason, _conn_state, _state) do
  #   :ok
  # end

  # @doc """
  # Sends an event to the WebSocket server per the Message protocol
  # """
  # def push(socket_pid, topic, event, msg) do
  #   Logger.debug "Socket Push: #{inspect topic}, #{inspect event}, #{inspect msg}"
  #   send socket_pid, {:send, %{topic: topic, event: event, payload: msg}}
  # end

  # defp json!(map), do: JSON.encode!(map)
end
