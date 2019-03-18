defmodule PhoenixClient.Message.V2 do
  alias PhoenixClient.Message

  def decode!([join_ref, ref, topic, event, payload | _]) do
    %Message{
      join_ref: join_ref,
      ref: ref,
      topic: topic,
      event: event,
      payload: payload
    }
  end

  def encode!(%Message{} = msg) do
    [msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload]
  end
end
