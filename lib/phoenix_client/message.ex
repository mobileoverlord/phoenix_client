defmodule PhoenixClient.Message do
  defstruct topic: nil,
            event: nil,
            payload: nil,
            channel_pid: nil,
            ref: nil,
            join_ref: nil

  def serializer("1.0.0"), do: __MODULE__.V1
  def serializer("2.0.0"), do: __MODULE__.V2

  def decode!(serializer, msg, json_library) do
    json_library.decode!(msg)
    |> serializer.decode!()
  end

  def encode!(serializer, %__MODULE__{} = msg, json_library) do
    serializer.encode!(msg)
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
