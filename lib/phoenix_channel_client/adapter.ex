defmodule PhoenixChannelClient.Adapter do
  use Behaviour

  defcallback open(url :: String.t, opts :: Keyword.t) ::
              {:ok, pid} |
              {:error, any}

  defcallback close ::
              {:ok, any} |
              {:error, any}

end
