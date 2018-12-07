defmodule PhoenixChannelClient do
  @type from :: {pid, tag :: term}

  @callback handle_in(event :: String.t(), payload :: map, state :: map) ::
              {:noreply, state :: map}

  @callback handle_reply(reply :: Tuple.t(), state :: map) :: {:noreply, state :: map}

  @callback handle_close(reply :: Tuple.t(), state :: map) ::
              {:noreply, state :: map}
              | {:stop, reason :: term, state :: map}

  require Logger

  @callback handle_call(request :: term, from, state :: term) ::
              {:reply, reply, new_state}
              | {:reply, reply, new_state, timeout | :hibernate | {:continue, term}}
              | {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate, {:continue, term}}
              | {:stop, reason, reply, new_state}
              | {:stop, reason, new_state}
            when reply: term, new_state: term, reason: term

  @callback handle_cast(request :: term, state :: term) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate | {:continue, term}}
              | {:stop, reason :: term, new_state}
            when new_state: term

  @callback handle_info(msg :: :timeout | term, state :: term) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate | {:continue, term}}
              | {:stop, reason :: term, new_state}
            when new_state: term

  defmacro __using__(_opts) do
    quote do
      alias PhoenixChannelClient.Server

      @behaviour unquote(__MODULE__)

      def child_spec({opts, genserver_opts}) do
        IO.inspect opts
        id = genserver_opts[:id] || __MODULE__
        %{
          id: id,
          restart: :permanent,
          shutdown: 5000,
          start: {__MODULE__, :start_link, [opts, genserver_opts]},
          type: :worker
        }
      end

      def start_link(opts, genserver_opts \\ []) do
        Server.start_link(__MODULE__, opts, genserver_opts)
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

      def handle_info(_message, state) do
        {:noreply, state}
      end

      def handle_call(_message, _from, state) do
        {:reply, :ok, state}
      end

      def handle_cast(_cast, state) do
        {:noreply, state}
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end

      defoverridable handle_in: 3,
                     handle_reply: 2,
                     handle_close: 2,
                     handle_info: 2,
                     handle_cast: 2,
                     handle_call: 3
    end
  end

  alias PhoenixChannelClient.Server

  def join(pid_or_name, params \\ %{}) do
    Server.join(pid_or_name, params)
  end

  def leave(pid_or_name) do
    Server.leave(pid_or_name)
  end

  def cancel_push(pid_or_name, push_ref) do
    Server.cancel_push(pid_or_name, push_ref)
  end

  def push(pid_or_name, event, payload, opts \\ []) do
    Server.push(pid_or_name, event, payload, opts)
  end

  def channel(sender, opts) do
    PhoenixChannelClient.Server.start_link(sender, opts)
  end

  def terminate(reason, _state) do
    Logger.warn("Channel terminated: #{reason}")
    :shutdown
  end
end
