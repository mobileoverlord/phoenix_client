defmodule PhoenixChannelClient.Mixfile do
  use Mix.Project

  def project do
    [
      app: :phoenix_channel_client,
      version: "0.3.0",
      elixir: "~> 1.0",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: [extras: ["README.md"], main: "readme"],
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:websocket_client, "~> 1.3", optional: true},
      {:phoenix, github: "phoenixframework/phoenix", tag: "v1.3.2", only: :test},
      {:jason, "~> 1.0", only: :test},
      {:cowboy, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.18.0", only: :dev}
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
