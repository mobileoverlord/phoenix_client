defmodule PhoenixClient.Mixfile do
  use Mix.Project

  def project do
    [
      app: :phoenix_client,
      version: "0.11.1",
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
    [
      extra_applications: [:logger, :ssl],
      mod: {PhoenixClient, []}
    ]
  end

  defp deps do
    [
      {:websocket_client, "~> 1.3"},
      {:jason, "~> 1.0", optional: true},
      {:phoenix, github: "phoenixframework/phoenix", tag: "v1.5.1", only: :test},
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
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/mobileoverlord/phoenix_client"}
    ]
  end
end
