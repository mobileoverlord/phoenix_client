defmodule PhoenixClient.Message do
  defstruct topic: nil,
            event: nil,
            payload: nil,
            channel_pid: nil,
            ref: nil,
            join_ref: nil

  def decode!(msg, json_library) do
    [join_ref, ref, topic, event, payload | _] = json_library.decode!(msg)

    %__MODULE__{
      join_ref: join_ref,
      ref: ref,
      topic: topic,
      event: event,
      payload: payload
    }
  end

  def encode!(%__MODULE__{} = msg, json_library) do
    [msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload]
    |> json_library.encode!()
  end

  def join(topic, params) do
    %__MODULE__{
      topic: topic,
      event: "phx_join",
      payload: params
    }
  end

  def leave(topic) do
    %__MODULE__{
      topic: topic,
      event: "phx_leave"
    }
  end
end
