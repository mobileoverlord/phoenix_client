defmodule Phoenix.Channel.Client.Push do
  defstruct [
    channel: nil,
    event: "",
    payload: %{},
    rec_hooks: [],
    sent: false,
    rev_response: nil,
    after_hook: nil
  ]

  # def on_receive(%__MODULE__{rec_hooks: rec_hooks} = push, event, func) do
  #   put_in(push.rec_hooks, [{event, func} | rec_hooks])
  # end

  # def on_after(%__MODULE__{rec_hooks: rec_hooks} = push, ms, func) do

  # end

end
