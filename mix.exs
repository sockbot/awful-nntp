defmodule AwfulNntp.MixProject do
  use Mix.Project

  def project do
    [
      app: :awful_nntp,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Something Awful forums to NNTP bridge",
      source_url: "https://github.com/sockbot/awful-nntp",
      homepage_url: "https://github.com/sockbot/awful-nntp",
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AwfulNntp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.4.0"},
      {:floki, "~> 0.35.0"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/sockbot/awful-nntp"}
    ]
  end
end
