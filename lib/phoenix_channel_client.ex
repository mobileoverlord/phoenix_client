defmodule PhoenixChannelClient do

  @callback handle_in(event :: String.t, payload :: map, state :: map) ::
              {:noreply, state :: map}

  @callback handle_reply(reply :: Tuple.t, state :: map) ::
              {:noreply, state :: map}

  @callback handle_close(reply :: Tuple.t, state :: map) ::
              {:noreply, state :: map} |
              {:stop, reason :: term, state :: map}

  defmacro __using__(_opts) do
    quote do
      alias PhoenixChannelClient.Server

      @behaviour unquote(__MODULE__)

      def start_link(opts) do
        Server.start_link(__MODULE__, opts)
      end

      def join(params \\ %{}) do
        Server.join(__MODULE__, params)
      end

      def leave do
        Server.leave(__MODULE__)
      end

      def cancel_push(push_ref) do
        Server.cancel_push(__MODULE__, push_ref)
      end

      def push(event, payload, opts \\ []) do
        Server.push(__MODULE__, event, payload, opts)
      end

      def handle_in(event, payload, state) do
        IO.inspect "Handle in: #{event} #{inspect payload}"
        {:noreply, state}
      end

      def handle_reply(payload, state) do
        {:noreply, state}
      end

      def handle_close(payload, state) do
        IO.inspect "Handle Close"
        {:noreply, state}
      end

      defoverridable handle_in: 3, handle_reply: 2, handle_close: 2
    end
  end

  def channel(sender, opts) do
    PhoenixChannelClient.Server.start_link(sender, opts)
  end

  def terminate(message, _state) do
    IO.puts "Terminate: #{inspect message}"
    :shutdown
  end
end
