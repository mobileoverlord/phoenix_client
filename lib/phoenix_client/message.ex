defmodule PhoenixClient.Message do
  @derive {Jason.Encoder, only: [:topic, :event, :payload, :ref]}
  defstruct topic: nil,
            event: nil,
            payload: nil,
            channel_pid: nil,
            ref: nil

  def decode!(message, json_library) do
    decoded = json_library.decode!(message)

    %__MODULE__{
      topic: decoded["topic"],
      event: decoded["event"],
      payload: decoded["payload"],
      ref: decoded["ref"]
    }
  end

  def encode!(message, json_library) do
    json_library.encode!(message)
  end
end
