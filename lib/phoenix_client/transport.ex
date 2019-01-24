defmodule PhoenixClient.Transport do
  @callback open(url :: String.t(), opts :: Keyword.t()) ::
              {:ok, pid}
              | {:error, any}

  @callback close(socket :: pid) ::
              {:ok, any}
              | {:error, any}
end
