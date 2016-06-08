defmodule Phoenix.Channel.Client do
  use Behaviour

  defcallback handle_in(event :: String.t, payload :: map, state :: map) ::
              {:noreply, state :: map}

  defcallback handle_reply(reply :: Tuple.t, state :: map) ::
              {:noreply, state :: map}

  defcallback handle_close(reply :: Tuple.t, state :: map) ::
              {:noreply, state :: map} |
              {:stop, reason :: term, state :: map}

  defmacro __using__(_opts) do
    quote do
      alias Phoenix.Channel.Client.Server

      @behaviour unquote(__MODULE__)

      def join(pid, params \\ %{}) do
        Server.join(pid, params)
      end

      def leave(pid) do
        Server.leave(pid)
      end

      def cancel_push(pid, push_ref) do
        Server.cancel_push(pid, push_ref)
      end

      def push(pid, event, payload, opts \\ []) do
        Server.push(pid, event, payload, opts)
      end

      def handle_in(event, payload, state) do
        {:noreply, state}
      end

      def handle_reply(payload, state) do
        {:noreply, state}
      end

      def handle_close(payload, state) do
        {:noreply, state}
      end

      defoverridable handle_in: 3, handle_reply: 2, handle_close: 2
    end
  end

  def channel(sender, opts) do
    Phoenix.Channel.Client.Server.start_link(sender, opts)
  end
end
