defmodule MakeupLmml.MixProject do
  use Mix.Project

  @app :makeup_lmml
  @version "0.1.1"
  @source_url "https://github.com/Oeditus/makeup_lmml"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() not in [:dev, :test],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/dialyzer.plt"},
        plt_add_deps: :app_tree,
        plt_core_path: ".dialyzer",
        list_unused_filters: true,
        ignore_warnings: ".dialyzer/ignore.exs"
      ],
      name: "MakeupLmml",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Makeup.Lexers.LmmlLexer.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp deps do
    [
      # Core
      {:makeup, "~> 1.0"},
      {:nimble_parsec, "~> 1.2.3 or ~> 1.3"},

      # Development and documentation
      {:makeup_elixir, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict"
      ]
    ]
  end

  defp description do
    """
    LMML (and Markdown) lexer for the Makeup syntax highlighter.
    Provides syntax highlighting for LMML narratives and Markdown documents
    in ExDoc and any other tool using Makeup.
    """
  end

  defp package do
    [
      name: @app,
      files: ~w(
        lib
        stuff
        .formatter.exs
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE
      ),
      licenses: ["MIT"],
      maintainers: ["Aleksei Matiushkin"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/#{@app}",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "LMML Language" => "https://github.com/Oeditus/lmml"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "stuff/img/logo-48.png",
      assets: %{"stuff/img" => "assets"},
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"],
      authors: ["Aleksei Matiushkin"],
      canonical: "https://hexdocs.pm/#{@app}"
    ]
  end
end
