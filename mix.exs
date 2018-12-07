defmodule PhoenixChannelClient.Mixfile do
  use Mix.Project

  def project do
    [
      app: :phoenix_channel_client,
      version: "0.4.0",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: [extras: ["README.md"], main: "readme"],
      deps: deps()
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:websocket_client, "~> 1.3", optional: true},
      {:phoenix, github: "phoenixframework/phoenix", tag: "v1.4.0", only: :test},
      {:jason, "~> 1.0", only: :test},
      {:plug_cowboy, "~> 2.0", only: :test},
      {:ex_doc, "~> 0.18", only: :dev}
    ]
  end

  defp description do
    """
    Connect to Phoenix Channels from Elixir
    """
  end

  defp package do
    [
      maintainers: ["Justin Schneck"],
      licenses: ["Apache 2.0"],
      links: %{"Github" => "https://github.com/mobileoverlord/phoenix_channel_client"}
    ]
  end
end
