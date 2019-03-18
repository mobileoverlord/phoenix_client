defmodule PhoenixClient.MessageTest do
  use ExUnit.Case, async: false

  alias PhoenixClient.Message

  describe "v1 serializer" do
    test "encode" do
      msg = %{
        ref: "1",
        topic: "1234",
        event: "new:thing",
        payload: %{"a" => "b"}
      }

      v1_msg = Message.V1.encode!(struct(Message, msg))
      assert msg == v1_msg
    end

    test "decode" do
      msg = %{
        "ref" => "1",
        "topic" => "1234",
        "event" => "new:thing",
        "payload" => %{"a" => "b"}
      }

      v1_msg = Message.V1.decode!(msg)
      assert to_struct(Message, msg) == v1_msg
    end
  end

  describe "v2 serializer" do
    test "encode" do
      msg = %{
        join_ref: "1",
        ref: "1",
        topic: "1234",
        event: "new:thing",
        payload: %{"a" => "b"}
      }

      v2_msg = Message.V2.encode!(struct(Message, msg))
      assert ["1", "1", "1234", "new:thing", %{"a" => "b"}] == v2_msg
    end

    test "decode" do
      msg = %{
        join_ref: "1",
        ref: "1",
        topic: "1234",
        event: "new:thing",
        payload: %{"a" => "b"}
      }

      v2_msg = Message.V2.decode!(["1", "1", "1234", "new:thing", %{"a" => "b"}])
      assert struct(Message, msg) == v2_msg
    end
  end

  def to_struct(kind, attrs) do
    struct = struct(kind)

    Enum.reduce(Map.to_list(struct), struct, fn {k, _}, acc ->
      case Map.fetch(attrs, Atom.to_string(k)) do
        {:ok, v} -> %{acc | k => v}
        :error -> acc
      end
    end)
  end
end
